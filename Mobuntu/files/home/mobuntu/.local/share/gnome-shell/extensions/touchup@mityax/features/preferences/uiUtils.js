import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';

var Align = Gtk.Align;
function buildPreferencesGroup(props) {
    const group = new Adw.PreferencesGroup({
        title: props.title,
        description: props.description ?? '',
    });
    props.children?.forEach(c => group.add(c));
    props.onCreated?.(group);
    return group;
}
function buildSwitchRow(props) {
    const row = new Adw.SwitchRow({
        title: props.title,
        subtitle: props.subtitle,
    });
    if ('setting' in props) {
        props.setting.bind(row, 'active', props.invert ? Gio.SettingsBindFlags.INVERT_BOOLEAN : undefined);
    }
    if ("initialValue" in props) {
        row.active = props.invert ? !props.initialValue : props.initialValue;
    }
    if ('onChanged' in props) {
        row.connect('notify::active', () => props.onChanged?.(props.invert ? !row.active : row.active));
    }
    props.onCreated?.(row);
    return row;
}
function buildSpinRow(props) {
    const row = new Adw.SpinRow({
        title: props.title,
        subtitle: props.subtitle,
        adjustment: props.adjustment,
    });
    if ('setting' in props) {
        props.setting.bind(row, 'value');
    }
    if ("initialValue" in props) {
        row.set_value(props.initialValue);
    }
    if ('onChanged' in props) {
        row.connect('value-changed', () => props.onChanged(row.get_value()));
    }
    props.onCreated?.(row);
    return row;
}
function buildComboRow(props) {
    const row = new Adw.ComboRow({
        title: props.title,
        subtitle: props.subtitle,
        model: new Gtk.StringList({
            strings: props.items.map(i => i.label),
        }),
    });
    const initialValue = "initialValue" in props
        ? props.initialValue
        : props.setting.get();
    const onChanged = () => {
        const newValue = props.items[row.selected].value;
        if ('onChanged' in props)
            props.onChanged(newValue);
        if ('setting' in props)
            props.setting.set(newValue);
    };
    row.set_selected(props.items.findIndex(i => i.value === initialValue));
    row.connect('notify::selected-item', onChanged);
    props.onCreated?.(row);
    return row;
}
function buildToggleButtonRow(props) {
    const row = new Adw.ActionRow({
        title: props.title,
        subtitle: props.subtitle,
    });
    const toggleGroup = [];
    const buttonBox = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL,
        cssClasses: ['linked'],
        valign: Align.CENTER,
    });
    const initialValue = "initialValue" in props
        ? props.initialValue
        : props.setting.get();
    const onChanged = (v) => {
        if ('onChanged' in props)
            props.onChanged(v);
        if ('setting' in props)
            props.setting.set(v);
    };
    props.items.forEach((item) => {
        const button = new Gtk.ToggleButton({
            label: item.label,
        });
        if (item.value === initialValue) {
            button.active = true;
        }
        button.connect('toggled', () => {
            if (button.active) {
                toggleGroup.forEach(b => {
                    if (b !== button) {
                        b.active = false;
                    }
                });
                onChanged(item.value);
            }
            else if (toggleGroup.every((b) => !b.active)) {
                button.active = true;
            }
        });
        toggleGroup.push(button);
        buttonBox.append(button);
    });
    row.add_suffix(buttonBox);
    row.set_activatable_widget(buttonBox);
    props.onCreated?.(row, toggleGroup);
    return row;
}

export { buildComboRow, buildPreferencesGroup, buildSpinRow, buildSwitchRow, buildToggleButtonRow };
