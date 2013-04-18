TARGET = qtmedia_avfoundation
QT += multimedia-private network

CONFIG += no_keywords

PLUGIN_TYPE = mediaservice
PLUGIN_CLASS_NAME = AVFServicePlugin
load(qt_plugin)

LIBS += -framework AppKit -framework AudioUnit \
        -framework AudioToolbox -framework CoreAudio \
        -framework QuartzCore -framework AVFoundation \
        -framework CoreMedia

include(common/common.pri)
include(camera/camera.pri)
include(mediaplayer/mediaplayer.pri)

HEADERS += avfserviceplugin.h
OBJECTIVE_SOURCES += avfserviceplugin.mm
OTHER_FILES += avfoundation.json

DEFINES += QMEDIA_AVFOUNDATION
