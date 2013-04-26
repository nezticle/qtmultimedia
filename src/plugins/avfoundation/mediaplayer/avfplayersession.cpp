#include "avfplayersession.h"

#import <AVFoundation/AVFoundation.h>

//AVAsset Keys
static NSString* const AVF_TRACKS_KEY = @"tracks";
static NSString* const AVF_READABLE_KEY = @"readable";

@interface AVFPlayerSessionObserver : NSObject
{
    AVFPlayerSession *m_session;
    AVURLAsset *m_asset;
}

-(AVFPlayerSessionObserver *) initWithPlayerSession:(AVFPlayerSession *)session;
-(void) setURL:(NSURL *)url;
-(void) unloadMedia;
-(void) assetLoadingCompleted:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys;
-(void) assetFailedToLoad:(NSError *)error;

@end

@implementation AVFPlayerSessionObserver

-(AVFPlayerSessionObserver *) initWithPlayerSession:(AVFPlayerSession *)session
{
    if (!(self = [super init]))
        return nil;

    self->m_session = session;
    return self;
}

-(void) setURL:(NSURL *)url
{
    //Create an asset for inspection of a resource referenced by a given URL.
    //Load the values for the asset keys "tracks", "playable".

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:m_URL options:nil];
    NSArray *requestedKeys = [NSArray arrayWithObjects:AVF_TRACKS_KEY, AVF_READABLE_KEY, nil];

    // Tells the asset to load the values of any of the specified keys that are not already loaded.
    [asset loadValuesAsynchronouslyForKeys:requestedKeys completionHandler: ^{
        dispatch_async( dispatch_get_main_queue(), ^{
            [self assetLoadingCompleted:asset withKeys:requestedKeys];
        });
    }];

}

-(void) unloadMedia
{
    //Called when media is set to null
}

-(void) assetLoadingCompleted:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys
{
    //Make sure that the value of each key has loaded successfully.
    for (NSString *thisKey in requestedKeys)
    {
        NSError *error = nil;
        AVKeyValueStatus keyStatus = [asset statusOfValueForKey:thisKey error:&error];
#ifdef QT_DEBUG_AVF
        qDebug() << Q_FUNC_INFO << [thisKey UTF8String] << " status: " << keyStatus;
#endif
        if (keyStatus == AVKeyValueStatusFailed)
        {
            [self assetFailedToLoad:error];
            return;
        }
    }

    //Use the AVAsset playable property to detect whether the asset can be played.
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << "isReadable: " << [asset isReadable];
#endif
    if (!asset->readable)
    {
        //Generate an error describing the failure.
        NSString *localizedDescription = NSLocalizedString(@"Item cannot be read", @"Item cannot be played read");
        NSString *localizedFailureReason = NSLocalizedString(@"The assets tracks were loaded, but could not be made readable.", @"Item cannot be played failure reason");
        NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:
                localizedDescription, NSLocalizedDescriptionKey,
                localizedFailureReason, NSLocalizedFailureReasonErrorKey,
                nil];
        NSError *assetCannotBePlayedError = [NSError errorWithDomain:@"StitchedStreamPlayer" code:0 userInfo:errorDict];

        [self assetFailedToLoad:assetCannotBePlayedError];

        return;
    }

    //Asset is loaded, and is readable
    self->m_asset = asset;
}

-(void) assetFailedToLoad:(NSError *)error
{
    Q_UNUSED(error)
    QMetaObject::invokeMethod(m_session, "processMediaLoadError", Qt::AutoConnection);
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO;
    qDebug() << [[error localizedDescription] UTF8String];
    qDebug() << [[error localizedFailureReason] UTF8String];
    qDebug() << [[error localizedRecoverySuggestion] UTF8String];
#endif
}

@end

AVFPlayerSession::AVFPlayerSession(AVFMediaPlayerService *service, QObject *parent = 0)
    : QObject(parent)
    , m_service(service)
    , m_videoOutput(0)
    , m_currentAsset(0)
    , m_state(QMediaPlayer::StoppedState)
    , m_mediaStatus(QMediaPlayer::NoMedia)
    , m_mediaStream(0)
    , m_muted(false)
    , m_tryingAsync(false)
    , m_volume(100)
    , m_rate(1.0)
    , m_videoAvailable(false)
    , m_audioAvailable(false)
    , m_currentAsset(0)
    , m_assetReader(0)
    , m_assetVideoOutputReaderTrack(0)
    , m_assetAudioOutputReaderTrack(0)
    , m_nativeDuration(0)
    , m_nativePosition(0)
    , m_nativePlaybackRange(0)
{
    m_observer = [[AVFPlayerSessionObserver alloc] initWidthPlayerSession:this];
}

AVFPlayerSession::~AVFPlayerSession()
{
}

void AVFPlayerSession::setVideoOutput(QMediaControl *output)
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << output;
#endif

    if (m_videoOutput == output)
        return;

    //TODO: let the video renderer know it has a new target

    m_videoOutput = output;
}

AVAsset *AVFPlayerSession::currentAsset()
{
    return m_currentAsset;
}

QMediaPlayer::State AVFPlayerSession::state() const
{
    return m_state;
}

QMediaPlayer::MediaStatus AVFPlayerSession::mediaStatus() const
{
    return m_mediaStatus;
}

QMediaContent AVFPlayerSession::media() const
{
    return m_resources;
}

const QIODevice *AVFPlayerSession::mediaStream() const
{
    return m_mediaStream;
}

void AVFPlayerSession::setMedia(const QMediaContent &content, QIODevice *stream)
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << content.canonicalUrl();
#endif

    m_resources = content;
    m_mediaStream = stream;

    QMediaPlayer::MediaStatus oldMediaStatus = m_mediaStatus;

    if (content.isNull() || content.canonicalUrl().isEmpty()) {
        [m_observer unloadMedia];
        m_mediaStatus = QMediaPlayer::NoMedia;
        if (m_state != QMediaPlayer::StoppedState)
            Q_EMIT stateChanged(m_state = QMediaPlayer::StoppedState);

        if (m_mediaStatus != oldMediaStatus)
            Q_EMIT mediaStatusChanged(m_mediaStatus);
        Q_EMIT positionChanged(position());
        return;
    } else {

        m_mediaStatus = QMediaPlayer::LoadingMedia;
        if (m_mediaStatus != oldMediaStatus)
            Q_EMIT mediaStatusChanged(m_mediaStatus);
    }
    //Load AVURLAsset
    //initialize asset using content's URL
    NSString *urlString = [NSString stringWithUTF8String:content.canonicalUrl().toEncoded().constData()];
    NSURL *url = [NSURL URLWithString:urlString];
    [m_observer setURL:url];
}

qint64 AVFPlayerSession::position() const
{
    //Convert m_nativePosition into milliseconds
    double seconds = m_nativePosition.value / m_nativePosition.timeScale;
    return qint64(seconds * 1000);
}

qint64 AVFPlayerSession::duration() const
{
    //Convert m_nativeDuration into milliseconds
    double seconds = m_nativeDuration.value / m_nativeDuration.timeScale;
    return qint64(seconds * 1000);
}

int AVFPlayerSession::bufferStatus() const
{
    //TODO: make use of bufferStatus if possible
    return 100;
}

int AVFPlayerSession::volume() const
{
    return m_volume;
}

bool AVFPlayerSession::isMuted() const
{
    return m_muted;
}

bool AVFPlayerSession::isAudioAvailable() const
{
    if (audioTrack() != nil)
        return true;
    return false;
}

bool AVFPlayerSession::isVideoAvailable() const
{
    if (videoTrack() != nil)
        return true;
    return false;
}

bool AVFPlayerSession::isSeekable() const
{
    //TODO: we should support seeking, as it is possible
    return false;
}

QMediaTimeRange AVFPlayerSession::availablePlaybackRanges() const
{
    return QMediaTimeRange(0, duration());
}

qreal AVFPlayerSession::playbackRate() const
{
    return m_rate;
}

void AVFPlayerSession::setPlaybackRate(qreal rate)
{
    if (qFuzzyCompare(m_rate, rate))
        return;

    //we dont support playing backwards
    if (rate < 0.0)
        m_rate = 0.0;
    else
        m_rate = rate;

}

void AVFPlayerSession::setPosition(qint64 pos)
{
    if ( !isSeekable() || pos == position())
        return;

    if (duration() > 0)
        pos = qMin(pos, duration());

    //TODO: finish implimentation of seeking
}

void AVFPlayerSession::play()
{
}

void AVFPlayerSession::pause()
{
}

void AVFPlayerSession::stop()
{
}

void AVFPlayerSession::setVolume(int volume)
{
}

void AVFPlayerSession::setMuted(bool muted)
{
}

void AVFPlayerSession::processAssetLoaded()
{
    //Asset has been loaded successfully
    //We can now use the asset to load the media
    m_currentAsset = m_observer->m_asset;

    //Reset position, duration, seekable, playbackRate
    resetAssetData();

    //Recreate the media readers (because we changed asset and start position)
    resetMediaReaders();
}

void AVFPlayerSession::processMediaLoadError()
{
    Q_EMIT error(QMediaPlayer::FormatError, tr("Failed to load media"));
    Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::InvalidMedia);
    Q_EMIT stateChanged(m_state = QMediaPlayer::StoppedState);
}


void AVFPlayerSession::resetAssetData()
{
    m_nativeDuration = [m_currentAsset duration];
    m_nativePosition = CMTimeMake(0, m_nativeDuration.timescale);
    m_nativePlaybackRange = CMTimeRangeMake(m_nativePosition, m_nativeDuration);

    Q_EMIT durationChanged(duration());
    Q_EMIT positionChanged(position());
}

void AVFPlayerSession::resetMediaReaders()
{
    //BUG: Release the current readers

    //Recreates the AVAssetReader infrastructure
    //This needs to be done when the asset changes
    //and when we seek to a new position
    NSError *error = nil;
    m_assetReader = [AVAssetReader assetReaderWithAsset:m_currentAsset error:&error];

    //Setup AVAssetReaderTrackOutput for the visual track
    AVAssetTrack *videoTrack = videoTrack();
    if (videoTrack != nil) {
        NSMutableDictionary *videoSettings = [NSMutableDictionary dictionary];
        [videoSettings setObject: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey: (NSString *)kCVPixelBufferPixelFormatTypeKey];
        m_assetVideoOutputReaderTrack = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:videoSettings];
        [m_assetReader addOutput:m_assetVideoOutputReaderTrack];
    }

    //Setup AVAssetReaderTrackOutput for the audio track
    AVAssetTrack *audioTrack = audioTrack();
    if (audioTrack != nil) {
        m_assetAudioOutputReaderTrack = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:nil];
        [m_assetReader addOutput:m_assetAudioOutputReaderTrack];
    }

    //TODO make sure the position values are set here
    //This is where the seek position needs to be set
    m_assetReader.timeRange = CMTimeRangeMake(m_nativePosition, m_nativeDuration);

    //Start the reader
    if ([m_assetReader startReading] == NO)
    {
        NSLog(@"Error reading reading from current asset");
        processMediaLoadError();
        return;
    }

    //Media is now ready to be played
    Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::LoadedMedia);
}

AVAssetTrack *AVFPlayerSession::videoTrack()
{
    //TODO: handle multiple available video tracks
    if (m_currentAsset) {
        NSArray *tracks = [m_currentAsset tracksWithMediaType:AVMediaTypeVideo];
        for (AVAssetTrack *track in tracks) {
            //return the first track
            return track;
        }

    }
    return nil;
}

AVAssetTrack *AVFPlayerSession::audioTrack()
{
    //TODO: handle multiple available audio tracks
    if (m_currentAsset) {
        NSArray *tracks = [m_currentAsset tracksWithMediaType:AVMediaTypeAudio];
        for (AVAssetTrack *track in tracks) {
            //return the first track
            return track;
        }
    }
    return nil;
}
