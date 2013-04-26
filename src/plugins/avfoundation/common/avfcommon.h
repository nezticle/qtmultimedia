#ifndef AVFCOMMON_H
#define AVFCOMMON_H

class CVPixelBufferVideoBuffer : public QAbstractVideoBuffer
{
public:
    CVPixelBufferVideoBuffer(CVPixelBufferRef buffer)
        : QAbstractVideoBuffer(NoHandle)
        , m_buffer(buffer)
        , m_mode(NotMapped)
    {
        CVPixelBufferRetain(m_buffer);
    }

    virtual ~CVPixelBufferVideoBuffer()
    {
        CVPixelBufferRelease(m_buffer);
    }

    MapMode mapMode() const { return m_mode; }

    uchar *map(MapMode mode, int *numBytes, int *bytesPerLine)
    {
        if (mode != NotMapped && m_mode == NotMapped) {
            CVPixelBufferLockBaseAddress(m_buffer, 0);

            if (numBytes)
                *numBytes = CVPixelBufferGetDataSize(m_buffer);

            if (bytesPerLine)
                *bytesPerLine = CVPixelBufferGetBytesPerRow(m_buffer);

            m_mode = mode;

            return (uchar*)CVPixelBufferGetBaseAddress(m_buffer);
        } else {
            return 0;
        }
    }

    void unmap()
    {
        if (m_mode != NotMapped) {
            m_mode = NotMapped;
            CVPixelBufferUnlockBaseAddress(m_buffer, 0);
        }
    }

private:
    CVPixelBufferRef m_buffer;
    MapMode m_mode;
};

class TextureVideoBuffer : public QAbstractVideoBuffer
{
public:
    TextureVideoBuffer(GLuint textureId)
        : QAbstractVideoBuffer(GLTextureHandle)
        , m_textureId(textureId)
    {}

    virtual ~TextureVideoBuffer() {}

    MapMode mapMode() const { return NotMapped; }
    uchar *map(MapMode, int*, int*) { return 0; }
    void unmap() {}

    QVariant handle() const
    {
        return QVariant::fromValue<unsigned int>(m_textureId);
    }

private:
    GLuint m_textureId;
};

#endif // AVFCOMMON_H
