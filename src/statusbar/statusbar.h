#ifndef STATUSBAR_H
#define STATUSBAR_H

#include "core/window/shellsurface.h"
#include "core/services/activity.h"
#include "core/wayland/strutspacer.h"

class StatusBar : public ShellSurface
{
    Q_OBJECT
    Q_PROPERTY(QRect screenRect READ screenRect NOTIFY screenRectChanged)
    Q_PROPERTY(bool twentyFourTime READ twentyFourTime NOTIFY twentyFourTimeChanged)

public:
    //! Thickness of the bar, in logical pixels. The background sampler needs
    //! the same value to average the strip of wallpaper the bar covers.
    static constexpr int Height = 32;

    explicit StatusBar(QQmlEngine *engine);

    QRect screenRect();
    bool twentyFourTime();

    void setBatteryPercentage(bool enabled);
    void setTwentyFourTime(bool t);
    Q_INVOKABLE void toggleSpotlight();
    Q_INVOKABLE void toggleControlCenter();

    void updateGeometry();
    void updateViewStruts();

signals:
    void screenRectChanged();
    void launchPadChanged();
    void twentyFourTimeChanged();
    void spotlightRequested();
    void controlCenterRequested();

private slots:
    void initState();

private:
    void setupGlobalShortcuts();

    QRect m_screenRect;
    Activity *m_acticity;
    bool m_twentyFourTime;
    StrutSpacer *m_strutSpacer;
};

#endif // STATUSBAR_H
