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

#include "avfvideoframerenderer.h"
#include "avfcommon.h"

#include <QtGui/QOffscreenSurface>
#include <QtGui/QOpenGLContext>

#ifdef QT_DEBUG_AVF
#include <QtCore/qdebug.h>
#endif

#import <AVFoundation/AVFoundation.h>

QT_USE_NAMESPACE

AVFVideoFrameRenderer::AVFVideoFrameRenderer(QObject *parent)
    : QObject(parent)
    , m_isTextureCacheEnabled(false)
    , m_glContext(0)
    , m_offscreenSurface(0)
{
}

AVFVideoFrameRenderer::~AVFVideoFrameRenderer()
{
    delete m_offscreenSurface;
    delete m_glContext;
}

void AVFVideoFrameRenderer::setTargetOpenGLContext(QOpenGLContext *shareContext)
{
    m_isTextureCacheEnabled = initRendererWithSharedContext(shareContext);
}

QVideoFrame AVFVideoFrameRenderer::renderSampleBufferToVideoFrame(const CMSampleBufferRef &sampleBuffer)
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    int height = CVPixelBufferGetHeight(imageBuffer);
    int width = CVPixelBufferGetWidth(imageBuffer);
    QAbstractVideoBuffer *buffer = 0;
    GLuint textureID;

    if (m_isTextureCacheEnabled) {
        //Use the super fast path that returns a OpenGL texture without an upload penalty
        CVPixelBufferLockBaseAddress(imageBuffer, 0);

        m_glContext->makeCurrent(m_offscreenSurface);

#if !defined(Q_OS_IOS) //OS X
        CVOpenGLTextureRef texture = 0;
        //BUG: may need to create an texture attribute dictionary to pass instead of NULL
        CVReturn error = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                    m_coreVideoTextureCache,
                                                                    imageBuffer,
                                                                    NULL,
                                                                    &texture);
        if (error || texture == 0) {
            qWarning("Failed to create texture with CVOpenGLTextureCacheCreateTextureFromImage");
            return QVideoFrame();
        }

        textureID = CVOpenGLTextureGetName(texture);

        //BUG: this may release the texture before we get a chance to use it, will have to test and see
        CVOpenGLTextureCacheFlush(m_coreVideoTextureCache, 0);
        CFRelease(texture);

#else //iOS
        CVOpenGLESTextureRef texture = 0;
        CVReturn error = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                      m_coreVideoTextureCache,
                                                                      imageBuffer,
                                                                      NULL,
                                                                      GL_TEXTURE_2D,
                                                                      GL_RGBA,
                                                                      width,
                                                                      height,
                                                                      GL_BGRA,
                                                                      GL_UNSIGNED_BYTE,
                                                                      0,
                                                                      &texture);
        if (error || texture = 0) {
            qWarning("Failed to create texture with CVOpenGLESTextureCacheCreateTextureFromImage");
            return QVideoFrame();
        }

        textureID = CVOpenGLESTextureGetName(texture);

        //BUG: this may release the texture before we get a chance to use it, will have to test and see
        CVOpenGLESTextureCacheFlush(m_coreVideoTextureCache, 0);
        CFRelease(texture);
#endif
        m_glContext->doneCurrent();
        buffer = new TextureVideoBuffer(textureID);
    } else {
        //Use the pixel data instead (still may be used with OpenGL, but always requires an upload)
        buffer = new CVPixelBufferVideoBuffer(imageBuffer);
    }

    QVideoFrame frame(buffer, QSize(width, height), QVideoFrame::Format_RGB32);
    return frame;
}

bool AVFVideoFrameRenderer::hasValidTargetOpenGLContext()
{
    return m_isTextureCacheEnabled;
}

bool AVFVideoFrameRenderer::initRendererWithSharedContext(QOpenGLContext *shareContext)
{
    //We need a valid OpenGL context in this thread to use the CVOpenGL(ES)TextureCache
    //to convert CMSampleBufferRef's into OpenGL textures we can use in the orginal context
    //which in our case is the shareContext value.  By creating an OpenGL context attached to
    //an offscreen surface, and sharing its data with the original context we can meet all
    //requirments.

    if (!shareContext)
        return false;
    if (m_offscreenSurface)
        delete m_offscreenSurface;
    if (m_glContext)
        delete m_glContext;

    //OffscreenSurfce
    m_offscreenSurface = new QOffscreenSurface();
    m_offscreenSurface->setFormat(shareContext->format());
    m_offscreenSurface->create();

    //OpenGL Context
    m_glContext = new QOpenGLContext();
    m_glContext->setFormat(m_offscreenSurface->requestedFormat());
    m_glContext->setShareContext(shareContext);
    if (!m_glContext->create()) {
        qWarning("failed to create QOpenGLContext for AVFVideoFrameRenderer");
        return false;
    }

    //CVOpenGL(ES)TextureChache
    m_glContext->makeCurrent(m_offscreenSurface);
    CVReturn error;
#if !defined(Q_OS_IOS) //OS X
    //Create the texture cache
    error = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, CGLGetCurrentContext(), CGLGetPixelFormat(CGLGetCurrentContext()), NULL, &m_coreVideoTextureCache);
#else //iOS
    //Create the texture cache
    error = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [EAGLContext currentContext] , NULL, &m_coreVideoTextureCache);
#endif

    m_glContext->doneCurrent();

    if (error) {
        qWarning("failed to create CVOpenGL(ES)TextureCache");
        return false;
    }

    return true;
}
