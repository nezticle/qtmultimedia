INCLUDEPATH += common

HEADERS += \
    common/avfvideooutput.h \
    common/avfvideorenderercontrol.h \
    common/avfvideoframerenderer.h \
    common/avfdisplaylink.h \
    common/avfcommon.h

OBJECTIVE_SOURCES += \
    common/avfvideooutput.mm \
    common/avfvideorenderercontrol.mm \
    common/avfvideoframerenderer.mm \
    common/avfdisplaylink.h

#qtHaveModule(widgets) {
#    QT += multimediawidgets-private opengl
#    HEADERS += \
#        common/avfvideowidgetcontrol.h \
#        common/avfvideowidget.h \

#    OBJECTIVE_SOURCES += \
#        common/avfvideowidgetcontrol.mm \
#        common/avfvideowidget.mm
#}
