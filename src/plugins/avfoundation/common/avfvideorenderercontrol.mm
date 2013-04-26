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

#include "avfvideorenderercontrol.h"
#include "avfdisplaylink.h"
#include "avfvideoframerenderer.h"
#include "avfcommon.h"

#include <QtGui/QOpenGLContext>
#include <QtMultimedia/qabstractvideobuffer.h>
#include <QtMultimedia/qabstractvideosurface.h>
#include <QtMultimedia/qvideosurfaceformat.h>
#include <QtCore/qdebug.h>

#import <AVFoundation/AVFoundation.h>

QT_BEGIN_NAMESPACE

AVFVideoRendererControl::AVFVideoRendererControl(QObject *parent)
    : QVideoRendererControl(parent)
    , m_surface(0)
    , m_videoFrameRenderer(0)
{
}

AVFVideoRendererControl::~AVFVideoRendererControl()
{
}

QAbstractVideoSurface *AVFVideoRendererControl::surface() const
{
    return m_surface;
}

void AVFVideoRendererControl::setSurface(QAbstractVideoSurface *surface)
{
#ifdef QT_DEBUG_AVF
    qDebug() << "Set video surface" << surface;
#endif

    if (surface == m_surface)
        return;

    if (m_surface && m_surface->isActive())
        m_surface->stop();

    m_surface = surface;

    if (m_videoFrameRenderer)
        delete m_videoFrameRenderer;

    if (m_surface) {
        m_videoFrameRenderer = new AVFVideoFrameRenderer(this);
    }
}

void AVFVideoRendererControl::processVideoSampleBuffer(const CMSampleBufferRef &sampleBuffer)
{
    //Get a handle to the OpenGL context for the new surface
    //It is OK for this to be null, as this means that we should
    //fallback to not using OpenGL.
    if (!m_videoFrameRenderer->hasValidTargetOpenGLContext()) {
        QOpenGLContext *surfaceContext = qobject_cast<QOpenGLContext*>(m_surface->property("GLContext").value<QObject*>());
        m_videoFrameRenderer->setTargetOpenGLContext(surfaceContext);
    }

    //BUG: Make sure that this works with NoHandle and GLTexture QVideoSurfaceFormats
    QVideoFrame frame = m_videoFrameRenderer->renderSampleBufferToVideoFrame(sampleBuffer);

    if (m_surface && frame.isValid()) {
        if (m_surface->isActive() && m_surface->surfaceFormat().pixelFormat() != frame.pixelFormat())
            m_surface->stop();

        if (!m_surface->isActive()) {
            QVideoSurfaceFormat format(frame.size(), frame.pixelFormat(), QAbstractVideoBuffer::NoHandle);

            if (!m_surface->start(format)) {
                qWarning("Failed to activate video surface");
            }
        }

        if (m_surface->isActive())
            m_surface->present(frame);
    }

}

QT_END_NAMESPACE

#include "moc_avfvideorenderercontrol.cpp"
