/****************************************************************************
**
** Copyright (C) 2013 Digia Plc and/or its subsidiary(-ies).
** Contact: http://www.qt-project.org/legal
**
** This file is part of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and Digia.  For licensing terms and
** conditions see http://qt.digia.com/licensing.  For further information
** use the contact form at http://qt.digia.com/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU Lesser General Public License version 2.1 requirements
** will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** In addition, as a special exception, Digia gives you certain additional
** rights.  These rights are described in the Digia Qt LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3.0 as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU General Public License version 3.0 requirements will be
** met: http://www.gnu.org/copyleft/gpl.html.
**
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include "avfmediaplayercontrol.h"
#include "avfmediaplayer.h"

//AVAsset Keys
static NSString* const AVF_TRACKS_KEY = @"tracks";
static NSString* const AVF_READABLE_KEY = @"readable";

@interface AVFMediaPlayerControlObserver : NSObject
{
    AVFMediaPlayerControl *m_session;
    AVURLAsset *m_asset;
}

@property (readonly, getter=asset) AVURLAsset *m_asset;

-(AVFMediaPlayerControlObserver *) initWithMediaPlayerControl:(AVFMediaPlayerControl *)session;
-(void) setURL:(NSURL *)url;
-(void) unloadMedia;
-(void) assetLoadingCompleted:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys;
-(void) assetFailedToLoad:(NSError *)error;

@end

@implementation AVFMediaPlayerControlObserver

@synthesize m_asset;

-(AVFMediaPlayerControlObserver *) initWithMediaPlayerControl:(AVFMediaPlayerControl *)session
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

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
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
    if (![asset isReadable])
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
    QMetaObject::invokeMethod(m_session, "processAssetLoaded", Qt::AutoConnection);
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

QT_BEGIN_NAMESPACE

AVFMediaPlayerControl::AVFMediaPlayerControl(AVFMediaPlayer *player, QObject *parent)
    : QMediaPlayerControl(parent)
    , m_player(player)
    , m_mediaStream(0)
{
    m_observer = [[AVFMediaPlayerControlObserver alloc] initWithMediaPlayerControl:this];

    connect(m_player, SIGNAL(positionChanged(qint64)), this, SIGNAL(positionChanged(qint64)));
    connect(m_player, SIGNAL(durationChanged(qint64)), this, SIGNAL(durationChanged(qint64)));
    connect(m_player, SIGNAL(stateChanged(QMediaPlayer::State)),
            this, SIGNAL(stateChanged(QMediaPlayer::State)));
    connect(m_player, SIGNAL(mediaStatusChanged(QMediaPlayer::MediaStatus)),
            this, SIGNAL(mediaStatusChanged(QMediaPlayer::MediaStatus)));
    connect(m_player, SIGNAL(volumeChanged(int)), this, SIGNAL(volumeChanged(int)));
    connect(m_player, SIGNAL(mutedChanged(bool)), this, SIGNAL(mutedChanged(bool)));
    connect(m_player, SIGNAL(audioAvailableChanged(bool)), this, SIGNAL(audioAvailableChanged(bool)));
    connect(m_player, SIGNAL(videoAvailableChanged(bool)), this, SIGNAL(videoAvailableChanged(bool)));
    connect(m_player, SIGNAL(error(int,QString)), this, SIGNAL(error(int,QString)));
}

AVFMediaPlayerControl::~AVFMediaPlayerControl()
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO;
#endif
}

QMediaPlayer::State AVFMediaPlayerControl::state() const
{
    return m_player->state();
}

QMediaPlayer::MediaStatus AVFMediaPlayerControl::mediaStatus() const
{
    return m_player->mediaStatus();
}

QMediaContent AVFMediaPlayerControl::media() const
{
    return m_resources;
}

const QIODevice *AVFMediaPlayerControl::mediaStream() const
{
    return m_mediaStream;
}

void AVFMediaPlayerControl::setMedia(const QMediaContent &content, QIODevice *stream)
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << content.canonicalUrl();
#endif

    m_resources = content;
    m_mediaStream = stream;

    if (content.isNull() || content.canonicalUrl().isEmpty()) {
        [m_observer unloadMedia];
        m_player->setAsset(0);
        return;
    }

    m_player->assetLoadingStarted();
    Q_EMIT mediaChanged(content);
    //Load AVURLAsset
    //initialize asset using content's URL
    NSString *urlString = [NSString stringWithUTF8String:content.canonicalUrl().toEncoded().constData()];
    NSURL *url = [NSURL URLWithString:urlString];
    [m_observer setURL:url];
}

qint64 AVFMediaPlayerControl::position() const
{
    return m_player->position();
}

qint64 AVFMediaPlayerControl::duration() const
{
    return m_player->duration();
}

int AVFMediaPlayerControl::bufferStatus() const
{
    return m_player->bufferStatus();
}

int AVFMediaPlayerControl::volume() const
{
    return m_player->volume();
}

bool AVFMediaPlayerControl::isMuted() const
{
    return m_player->isMuted();
}

bool AVFMediaPlayerControl::isAudioAvailable() const
{
    return m_player->isAudioAvailable();
}

bool AVFMediaPlayerControl::isVideoAvailable() const
{
    return m_player->isVideoAvailable();
}

bool AVFMediaPlayerControl::isSeekable() const
{
    return m_player->isSeekable();
}

QMediaTimeRange AVFMediaPlayerControl::availablePlaybackRanges() const
{
    return m_player->availablePlaybackRanges();
}

qreal AVFMediaPlayerControl::playbackRate() const
{
    return m_player->playbackRate();
}

void AVFMediaPlayerControl::setPlaybackRate(qreal rate)
{
    m_player->setPlaybackRate(rate);
}

void AVFMediaPlayerControl::setPosition(qint64 pos)
{
    m_player->setPosition(pos);
}

void AVFMediaPlayerControl::play()
{
    m_player->play();
}

void AVFMediaPlayerControl::pause()
{
    m_player->pause();
}

void AVFMediaPlayerControl::stop()
{
    m_player->stop();
}

void AVFMediaPlayerControl::setVolume(int volume)
{
    m_player->setVolume(volume);
}

void AVFMediaPlayerControl::setMuted(bool muted)
{
    m_player->setMuted(muted);
}

void AVFMediaPlayerControl::processAssetLoaded()
{
    m_player->setAsset([m_observer asset]);
}

void AVFMediaPlayerControl::processMediaLoadError()
{
    m_player->assetLoadingFailed();
}

QT_END_NAMESPACE

#include "moc_avfmediaplayercontrol.cpp"
