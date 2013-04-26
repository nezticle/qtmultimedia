#include "avfmediaplayer.h"
#include "avfvideooutput.h"
#include "avfdisplaylink.h"

#include <QtCore/QDebug>

QT_BEGIN_NAMESPACE

AVFMediaPlayer::AVFMediaPlayer(QObject *parent)
    : QObject(parent)
    , m_muted(false)
    , m_volume(50)
    , m_playbackRate(1.0)
    , m_state(QMediaPlayer::StoppedState)
    , m_mediaStatus(QMediaPlayer::NoMedia)
    , m_videoOutput(0)
    , m_currentAsset(0)
    , m_assetReader(0)
    , m_assetVideoOutputReaderTrack(0)
    , m_assetAudioOutputReaderTrack(0)
{
    m_displayLink = new AVFDisplayLink(this);
    connect(m_displayLink, SIGNAL(tick(CVTimeStamp)), SLOT(processVideoQueue(CVTimeStamp)), Qt::DirectConnection);
}

void AVFMediaPlayer::setVideoOutput(AVFVideoOutput *output)
{
    //TODO: let the video renderer know it has a new target
    m_videoOutput = output;
}

AVAsset *AVFMediaPlayer::currentAsset()
{
    return m_currentAsset;
}

void AVFMediaPlayer::setAsset(AVAsset *asset)
{
    //Asset has been loaded successfully
    //We can now use the asset to load the media
    if (m_currentAsset) {
        [m_currentAsset release];
        m_currentAsset = 0;
    }

    m_currentAsset = asset;
    [m_currentAsset retain];

    if (asset == nil) {
        m_mediaStatus = QMediaPlayer::NoMedia;
        if (m_state != QMediaPlayer::StoppedState)
            Q_EMIT stateChanged(m_state = QMediaPlayer::StoppedState);

        Q_EMIT mediaStatusChanged(m_mediaStatus);
        Q_EMIT positionChanged(position());
    }

    //Reset position, duration, seekable, playbackRate
    resetAssetData();

    //Recreate the media readers (because we changed asset and start position)
    resetMediaReaders();
}

qreal AVFMediaPlayer::playbackRate() const
{
    return m_playbackRate;
}

QMediaTimeRange AVFMediaPlayer::availablePlaybackRanges() const
{
    return QMediaTimeRange(0, duration());
}

bool AVFMediaPlayer::isSeekable() const
{
    return true;
}

bool AVFMediaPlayer::isVideoAvailable() const
{
    if (videoTrack() != nil)
        return true;
    return false;
}

bool AVFMediaPlayer::isAudioAvailable() const
{
    if (audioTrack() != nil)
        return true;
    return false;
}

bool AVFMediaPlayer::isMuted() const
{
    return m_muted;
}

int AVFMediaPlayer::volume() const
{
    return m_volume;
}

int AVFMediaPlayer::bufferStatus() const
{
    //TODO: make use of bufferStatus if possible
    return 100;
}

qint64 AVFMediaPlayer::duration() const
{
    if (m_nativeDuration.timescale == 0)
        return 0;

    //Convert m_nativeDuration into milliseconds
    double seconds = (double)m_nativeDuration.value / m_nativeDuration.timescale;
    return qint64(seconds * 1000);
}

qint64 AVFMediaPlayer::position() const
{
    if (m_nativePosition.timescale == 0)
        return 0;

    //Convert m_nativePosition into milliseconds
    double seconds = (double)m_nativePosition.value / m_nativePosition.timescale;
    return qint64(seconds * 1000);
}

QMediaPlayer::State AVFMediaPlayer::state() const
{
    return m_state;
}

QMediaPlayer::MediaStatus AVFMediaPlayer::mediaStatus() const
{
    return m_mediaStatus;
}

void AVFMediaPlayer::setPlaybackRate(qreal rate)
{
    if (qFuzzyCompare(m_playbackRate, rate))
        return;

    //we dont support playing backwards
    if (rate < 0.0)
        m_playbackRate = 0.0;
    else
        m_playbackRate = rate;

    //TODO: notify rendering of new playback rate
}

void AVFMediaPlayer::setPosition(qint64 pos)
{
    if ( !isSeekable() || pos == position())
        return;

    if (duration() > 0)
        pos = qMin(pos, duration());

    //Reset location of m_nativePositon to new time value
    m_nativePosition.value = pos / 1000 * m_nativePosition.timescale;

    //Reset the media readers at new m_nativePostion;
    resetMediaReaders();

    //TODO: notify renderer of new position
    Q_EMIT positionChanged(position());
}

void AVFMediaPlayer::setVolume(int volume)
{
    if (m_volume == volume)
        return;

    if (volume < 0)
        volume = 0;
    else if (volume > 100)
        volume = 100;

    m_volume = volume;

    //TODO: notify renderer of new volume
}

void AVFMediaPlayer::setMuted(bool muted)
{
    if (m_muted == muted)
        return;

    m_muted = muted;

    //TODO: notify renderer of new mute state
}

void AVFMediaPlayer::assetLoadingStarted()
{
    Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::LoadingMedia);
}

void AVFMediaPlayer::assetLoadingFailed()
{
    Q_EMIT error(QMediaPlayer::FormatError, tr("Failed to load media"));
    Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::InvalidMedia);
    Q_EMIT stateChanged(m_state = QMediaPlayer::StoppedState);
}

void AVFMediaPlayer::play()
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << "currently: " << m_state;
#endif

    if (m_state == QMediaPlayer::PlayingState)
        return;

    m_state = QMediaPlayer::PlayingState;

    //reset the EndOfMedia status if the same file is played again
    if (m_mediaStatus == QMediaPlayer::EndOfMedia) {
        setPosition(0);
        Q_EMIT positionChanged(position());
        //BUG: m_mediaStatus needs to be changed from EndOfMedia
    }

    if (m_mediaStatus == QMediaPlayer::LoadedMedia || m_mediaStatus == QMediaPlayer::BufferedMedia) {
        //Make sure that the video processing pipeline is active
        m_displayLink->start();
        //TODO: Make sure that the audio processing pipeline is active
    }

    //Make sure that we notify of state changes
    Q_EMIT stateChanged(m_state);
}

void AVFMediaPlayer::pause()
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << "currently: " << m_state;
#endif

    if (m_state == QMediaPlayer::PausedState)
        return;

    m_state = QMediaPlayer::PausedState;

    //Make sure that the video processing pipeline is stopped
    m_displayLink->stop();
    //Make sure that the audio processing pipeline is stopped

    //Make sure that we notify of state changes
    Q_EMIT stateChanged(m_state);
}

void AVFMediaPlayer::stop()
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << "currently: " << m_state;
#endif

    if (m_state == QMediaPlayer::StoppedState)
        return;

    m_state = QMediaPlayer::StoppedState;

    m_playbackRate = 0.0f;
    setPosition(0);


    //Make sure that the video processing pipeline is stopped
    m_displayLink->stop();

    //Make sure that the audio processing pipeline is stopped

    //Make sure the position is reset to 0

    //Make sure that we notify of state changes
    Q_EMIT stateChanged(m_state);
}

void AVFMediaPlayer::processVideoQueue(const CVTimeStamp &timeStamp)
{
    //This method is called once every vsync and provies a timeStamp of
    //when the frame will be displayed.  This is useful for the video queue
    //because this will occur at the maximum framerate that we can display
    //video frames.

    //Return time elapsed in seconds since last time processVideoQueue was called
    //Should be ~ 0.016 when monitor refresh is 60Hz
    double timeElapsedSinceLastFrame = timeStamp.videoRefreshPeriod * timeStamp.rateScalar / timeStamp.videoTimeScale;

    //Add the time elapsed to the current native position.
    m_nativePosition.value = m_nativePosition.value + (timeElapsedSinceLastFrame * m_nativePosition.timescale);

    //If the queue is empty pull another video sample

    //If queue is not full, try pull another video sample
    if (m_videoSampleBufferQueue.count() < 3) {
        //Check that the reader is capable of reading:
        if (m_assetReader.status == AVAssetReaderStatusReading ) {
            CMSampleBufferRef sampleBufferRef = [m_assetVideoOutputReaderTrack copyNextSampleBuffer];
            if (sampleBufferRef) {
                m_videoSampleBufferQueue.enqueue(sampleBufferRef);
            } else {
                //TODO: find out why copyNextSampleBuffer failed
            }

        } else  if (m_assetReader.status == AVAssetReaderStatusCompleted) {
            //EOS condtion
        } else {
            //Error condition
        }
    }

    //Check the local Video Samplebuffer queue for the oldest sample
    while (!m_videoSampleBufferQueue.isEmpty()) {
        CMSampleBufferRef sampleBufferRef = m_videoSampleBufferQueue.first();
        CMTime currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBufferRef);

        double sampleTimeInSeconds = (double)currentSampleTime.value / currentSampleTime.timescale;
        double positionInSeconds = (double)m_nativePosition.value / m_nativePosition.timescale;

        if ((sampleTimeInSeconds > (positionInSeconds - timeElapsedSinceLastFrame)) && (sampleTimeInSeconds < (positionInSeconds + timeElapsedSinceLastFrame))) {
            //If sampleTimeInSeconds lands between +/- timeElapsedSinceLast frame, show the frame
            if (m_videoOutput)
                m_videoOutput->processVideoSampleBuffer(sampleBufferRef);
            m_videoSampleBufferQueue.dequeue();
            CMSampleBufferInvalidate(sampleBufferRef);
            CFRelease(sampleBufferRef);
        } else if (sampleTimeInSeconds < (positionInSeconds - timeElapsedSinceLastFrame)) {
            //If sampleTimeInSeconds is too old
            m_videoSampleBufferQueue.dequeue();
            CMSampleBufferInvalidate(sampleBufferRef);
            CFRelease(sampleBufferRef);
        } else {
            //Make sure the current sample stays queued
            break;
        }
    }
}

void AVFMediaPlayer::processAudioQueue(const CVTimeStamp &timeStamp)
{

}

void AVFMediaPlayer::resetAssetData()
{
    m_nativeDuration = [m_currentAsset duration];
    m_nativePosition = CMTimeMake(0, m_nativeDuration.timescale);
    m_nativePlaybackRange = CMTimeRangeMake(m_nativePosition, m_nativeDuration);

    Q_EMIT durationChanged(duration());
    Q_EMIT positionChanged(position());
}

void AVFMediaPlayer::resetMediaReaders()
{
    //BUG: Release the current readers
    if (m_assetReader) {
        [m_assetReader release];
        m_assetReader = 0;
    }
    if (m_assetVideoOutputReaderTrack) {
        [m_assetVideoOutputReaderTrack release];
        m_assetVideoOutputReaderTrack = 0;
    }
    if (m_assetAudioOutputReaderTrack) {
        [m_assetAudioOutputReaderTrack release];
        m_assetAudioOutputReaderTrack = 0;
    }

    //Clear the video buffer queue
    while(!m_videoSampleBufferQueue.isEmpty()) {
        CMSampleBufferRef sampleBufferRef = m_videoSampleBufferQueue.dequeue();
        CMSampleBufferInvalidate(sampleBufferRef);
        CFRelease(sampleBufferRef);
    }

    if (m_currentAsset == nil)
        return;

    //Recreates the AVAssetReader infrastructure
    //This needs to be done when the asset changes
    //and when we seek to a new position
    NSError *readerError = nil;
    m_assetReader = [AVAssetReader assetReaderWithAsset:m_currentAsset error:&readerError];
    [m_assetReader retain];

    //Setup AVAssetReaderTrackOutput for the visual track
    AVAssetTrack *currentVideoTrack = videoTrack();
    if (currentVideoTrack != nil) {
        NSMutableDictionary *videoSettings = [NSMutableDictionary dictionary];
        [videoSettings setObject: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey: (NSString *)kCVPixelBufferPixelFormatTypeKey];
        m_assetVideoOutputReaderTrack = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:currentVideoTrack outputSettings:videoSettings];
        [m_assetVideoOutputReaderTrack retain];
        [m_assetReader addOutput:m_assetVideoOutputReaderTrack];
    }

    //Setup AVAssetReaderTrackOutput for the audio track
    AVAssetTrack *currentAudioTrack = audioTrack();
    if (currentAudioTrack != nil) {
        m_assetAudioOutputReaderTrack = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:currentAudioTrack outputSettings:nil];
        [m_assetAudioOutputReaderTrack retain];
        [m_assetReader addOutput:m_assetAudioOutputReaderTrack];
    }

    //TODO make sure the position values are set here
    //This is where the seek position needs to be set
    m_assetReader.timeRange = CMTimeRangeMake(m_nativePosition, m_nativeDuration);

    //Start the reader
    if ([m_assetReader startReading] == NO)
    {
        NSLog(@"Error reading reading from current asset");
        Q_EMIT error(QMediaPlayer::FormatError, tr("Failed to load media"));
        Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::InvalidMedia);
        Q_EMIT stateChanged(m_state = QMediaPlayer::StoppedState);
        return;
    }

    //Media is now ready to be played
    Q_EMIT mediaStatusChanged(m_mediaStatus = QMediaPlayer::LoadedMedia);
}

AVAssetTrack *AVFMediaPlayer::videoTrack() const
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

AVAssetTrack *AVFMediaPlayer::audioTrack() const
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

QT_END_NAMESPACE

#include "moc_avfmediaplayer.cpp"
