import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import ExtensionFeature from '../core/extensionFeature.js';

class NotificationService extends ExtensionFeature {
    notificationSource = null;
    constructor(pm) {
        super(pm);
    }
    create(props) {
        return new MessageTray.Notification({
            ...props,
            source: this.getNotificationSource(),
        });
    }
    show(notification) {
        this.getNotificationSource().addNotification(notification);
    }
    getNotificationSource() {
        if (!this.notificationSource) {
            this.notificationSource = new MessageTray.Source({
                title: 'TouchUp',
                // An icon for the source, used a fallback by notifications
                icon: new Gio.ThemedIcon({ name: 'dialog-information' }),
                iconName: 'dialog-information',
                policy: new MessageTray.NotificationGenericPolicy(),
            });
            this.pm.patch(() => {
                Main.messageTray.add(this.notificationSource);
                // Destroy the notification source when the extension is disabled:
                return () => this.notificationSource?.destroy(MessageTray.NotificationDestroyedReason.SOURCE_CLOSED);
            });
            // Reset the notification source if it's destroyed
            this.notificationSource.connect('destroy', _source => this.notificationSource = null);
        }
        return this.notificationSource;
    }
}

export { NotificationService };
