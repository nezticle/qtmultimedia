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

#ifndef AVFMEDIAPLAYER_H
#define AVFMEDIAPLAYER_H

#include <QtCore/QObject>
#include <QtCore/QQueue>
#include <QtMultimedia/QMediaTimeRange>
#include <QtMultimedia/QMediaPlayer>

#include <AVFoundation/AVFoundation.h>

QT_BEGIN_NAMESPACE

class QMediaControl;
class AVFVideoOutput;
class AVFDisplayLink;

class AVFMediaPlayer : public QObject
{
    Q_OBJECT
public:
    explicit AVFMediaPlayer(QObject *parent = 0);
    
    void setVideoOutput(AVFVideoOutput *output);

    AVAsset *currentAsset();
    void setAsset(AVAsset *asset);

    qreal playbackRate() const;
    QMediaTimeRange availablePlaybackRanges() const;
    bool isSeekable() const;
    bool isVideoAvailable() const;
    bool isAudioAvailable() const;
    bool isMuted() const;
    int volume() const;
    int bufferStatus() const;
    qint64 duration() const;
    qint64 position() const;
    QMediaPlayer::State state() const;
    QMediaPlayer::MediaStatus mediaStatus() const;

Q_SIGNALS:
    void positionChanged(qint64 position);
    void durationChanged(qint64 duration);
    void stateChanged(QMediaPlayer::State newState);
    void mediaStatusChanged(QMediaPlayer::MediaStatus status);
    void volumeChanged(int volume);
    void mutedChanged(bool muted);
    void audioAvailableChanged(bool audioAvailable);
    void videoAvailableChanged(bool videoAvailable);
    void error(int error, const QString &errorString);
    
public Q_SLOTS:
    void setPlaybackRate(qreal rate);
    void setPosition(qint64 pos);
    void setVolume(int volume);
    void setMuted(bool muted);

    void assetLoadingStarted();
    void assetLoadingFailed();

    void play();
    void pause();
    void stop();

private Q_SLOTS:
    void processVideoQueue(const CVTimeStamp &timeStamp);
    void processAudioQueue(const CVTimeStamp &timeStamp);

private:
    void resetAssetData();
    void resetMediaReaders();
    AVAssetTrack *videoTrack() const;
    AVAssetTrack *audioTrack() const;

    bool m_muted;
    int m_volume;
    qreal m_playbackRate;
    QMediaPlayer::State m_state;
    QMediaPlayer::MediaStatus m_mediaStatus;

    AVFVideoOutput *m_videoOutput;
    AVFDisplayLink *m_displayLink;

    AVAsset *m_currentAsset;
    AVAssetReader *m_assetReader;
    AVAssetReaderTrackOutput *m_assetVideoOutputReaderTrack;
    AVAssetReaderTrackOutput *m_assetAudioOutputReaderTrack;
    CMTime m_nativeDuration;
    CMTime m_nativePosition;
    CMTimeRange m_nativePlaybackRange;

    QQueue<CMSampleBufferRef> m_videoSampleBufferQueue;
    QQueue<CMSampleBufferRef> m_audioSampleBufferQueue;
};

QT_END_NAMESPACE

#endif // AVFMEDIAPLAYER_H
