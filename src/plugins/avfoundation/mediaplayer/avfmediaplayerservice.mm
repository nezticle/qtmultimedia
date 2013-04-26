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

#include "avfmediaplayerservice.h"
#include "avfmediaplayercontrol.h"
#include "avfmediaplayermetadatacontrol.h"
#include "avfmediaplayer.h"
#include "avfvideorenderercontrol.h"

//#ifndef QT_NO_WIDGETS
//#include "avfvideowidgetcontrol.h"
//#endif

QT_BEGIN_NAMESPACE

AVFMediaPlayerService::AVFMediaPlayerService(QObject *parent)
    : QMediaService(parent)
    , m_videoOutput(0)
{
    m_player = new AVFMediaPlayer(this);
    m_control = new AVFMediaPlayerControl(m_player, this);
    m_playerMetaDataControl = new AVFMediaPlayerMetaDataControl(m_player, this);

    m_videoRenderer = new AVFVideoRendererControl(this);
//#if defined(HAVE_WIDGETS)
//    m_videoWidget = new AVFVideoWidgetControl(this);
//#endif

    connect(m_control, SIGNAL(mediaChanged(QMediaContent)), m_playerMetaDataControl, SLOT(updateTags()));
}

AVFMediaPlayerService::~AVFMediaPlayerService()
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO;
#endif
}

QMediaControl *AVFMediaPlayerService::requestControl(const char *name)
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << name;
#endif

    if (qstrcmp(name, QMediaPlayerControl_iid) == 0)
        return m_control;

    if (qstrcmp(name, QMetaDataReaderControl_iid) == 0)
        return m_playerMetaDataControl;

    //TODO: Add QMediaVideoProbeControl_iid
    //TODO: Add QMediaAudioProbeControl_iid

    if (!m_videoOutput) {
        if (qstrcmp(name, QVideoRendererControl_iid) == 0)
            m_videoOutput = m_videoRenderer;
//#if defined(HAVE_WIDGETS)
//        else if (qstrcmp(name, QVideoWidgetControl_iid) == 0)
//            m_videoOutput = m_videoWidget;
//#endif
        if (m_videoOutput) {
            m_player->setVideoOutput(qobject_cast<AVFVideoOutput*>(m_videoOutput));
            return m_videoOutput;
        }
    }

    return 0;
}

void AVFMediaPlayerService::releaseControl(QMediaControl *control)
{
#ifdef QT_DEBUG_AVF
    qDebug() << Q_FUNC_INFO << control;
#endif

    if (m_videoOutput == control) {
        m_videoOutput = 0;
        m_player->setVideoOutput(0);
    }

    //TODO: Detache Video probe here
    //TODO: Detache Audio probe here
}

QT_END_NAMESPACE
