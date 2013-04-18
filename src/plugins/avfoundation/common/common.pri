INCLUDEPATH += common

HEADERS += \
    common/avfvideorenderercontrol.h \
    common/avfdisplaylink.h \
    common/avfvideoframerenderer.h \
    common/avfvideooutput.h

OBJECTIVE_SOURCES += \
    common/avfvideorenderercontrol.mm \
    common/avfdisplaylink.mm \
    common/avfvideoframerenderer.mm \
    common/avfvideooutput.mm

qtHaveModule(widgets) {
    QT += multimediawidgets-private opengl
    HEADERS += \
        common/avfvideowidgetcontrol.h \
        common/avfvideowidget.h

    OBJECTIVE_SOURCES += \
        common/avfvideowidgetcontrol.mm \
        common/avfvideowidget.mm
}
