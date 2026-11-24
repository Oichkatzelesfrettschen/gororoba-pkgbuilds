# CachyOS Desktop Ricing Guide with Orchis Theme

## CachyOS Default Color Scheme

CachyOS uses a **Nord-based color palette** with cyan/blue accents that creates a cohesive, professional appearance.

### Official CachyOS Colors

Based on CachyOS branding and default themes:

```css
/* CachyOS Nord Color Palette */
--cachyos-primary: #88C0D0;      /* Cyan/Blue (Nord8) */
--cachyos-accent: #5E81AC;       /* Blue (Nord10) */
--cachyos-background: #2E3440;   /* Dark grey (Nord0) */
--cachyos-surface: #3B4252;      /* Lighter grey (Nord1) */
--cachyos-text: #ECEFF4;         /* Off-white (Nord6) */

/* Additional Nord Colors */
--nord-green: #A3BE8C;           /* Nord14 */
--nord-yellow: #EBCB8B;          /* Nord13 */
--nord-orange: #D08770;          /* Nord12 */
--nord-red: #BF616A;             /* Nord11 */
--nord-purple: #B48EAD;          /* Nord15 */
```

## OLED-Optimized Pure Black Theme

For OLED displays (like your RTX 4070 Ti connected monitor), use pure black backgrounds to:
- **Save power**: Black pixels consume no power on OLED
- **Reduce eye strain**: True black reduces glare
- **Increase contrast**: Perfect blacks enhance color vibrancy

### Recommended Orchis Variant for OLED

Install `Orchis-Dark` with the `--tweaks black` flag for pure black backgrounds:

```bash
# Already included in orchis-gtk-theme-full package
gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Dark"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
```

### CachyOS + Orchis Integration

To match CachyOS Nord branding with Orchis:

1. **Use Teal variant** (closest to CachyOS cyan):
   ```bash
   gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Teal-Dark"
   ```

2. **Or use Grey variant** with Nord accent colors:
   ```bash
   gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Grey-Dark"
   ```

## Complete CachyOS Ricing Stack

### 1. Theme: Orchis GTK Theme (✓ Installed)

```bash
# OLED-optimized pure black
gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Dark"

# CachyOS Nord-inspired teal
gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Teal-Dark"
```

### 2. Icons: Papirus Icon Theme

```bash
sudo pacman -S papirus-icon-theme

# Cyan variant (matches CachyOS branding)
git clone https://github.com/PapirusDevelopmentTeam/papirus-folders
cd papirus-folders
./papirus-folders -C cyan --theme Papirus-Dark

gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
```

### 3. Cursor: Vimix Cursors

```bash
yay -S vimix-cursors

gsettings set org.gnome.desktop.interface cursor-theme "Vimix-cursors"
```

### 4. Shell Theme: Orchis GNOME Shell

```bash
# Enable User Themes extension
yay -S gnome-shell-extension-user-theme

gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com

gsettings set org.gnome.shell.extensions.user-theme name "Orchis-Dark"
```

### 5. Fonts: CachyOS Font Configuration

```bash
# Install recommended fonts
sudo pacman -S ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji

# For better rendering
gsettings set org.gnome.desktop.interface font-name "Cantarell 11"
gsettings set org.gnome.desktop.interface document-font-name "Sans 11"
gsettings set org.gnome.desktop.interface monospace-font-name "Monospace 10"
```

### 6. Terminal: Kitty with Dracula/Nord Theme

```bash
sudo pacman -S kitty

# Configure Nord theme
mkdir -p ~/.config/kitty
cat > ~/.config/kitty/kitty.conf << 'EOF'
# Nord Color Scheme for Kitty
foreground            #D8DEE9
background            #000000
selection_foreground  #000000
selection_background  #FFFACD
url_color             #0087BD
cursor                #81A1C1

# Black
color0   #3B4252
color8   #4C566A

# Red
color1   #BF616A
color9   #BF616A

# Green
color2   #A3BE8C
color10  #A3BE8C

# Yellow
color3   #EBCB8B
color11  #EBCB8B

# Blue
color4   #81A1C1
color12  #81A1C1

# Magenta
color5   #B48EAD
color13  #B48EAD

# Cyan
color6   #88C0D0
color14  #8FBCBB

# White
color7   #E5E9F0
color15  #ECEFF4

# Font
font_family      JetBrains Mono
font_size        11.0
EOF
```

### 7. Conky System Monitor (Optional)

```bash
sudo pacman -S conky

# Create minimal config
mkdir -p ~/.config/conky
cat > ~/.config/conky/conky.conf << 'EOF'
conky.config = {
    alignment = 'top_right',
    background = true,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = '88C0D0',  -- CachyOS cyan
    default_outline_color = '2E3440',
    default_shade_color = '2E3440',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    gap_x = 20,
    gap_y = 60,
    minimum_height = 5,
    minimum_width = 5,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 0,
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
    xftalpha = 0.8,
    font = 'DejaVu Sans Mono:size=10',
}

conky.text = [[
${color 88C0D0}${font :size=14}CachyOS ${alignr}${font :size=10}${time %H:%M}${color}
${hr 2}
${color 88C0D0}CPU${color} $alignr $cpu%
${cpubar 4}
${color 88C0D0}RAM${color} $alignr $mem/$memmax
${membar 4}
${color 88C0D0}Disk${color} $alignr ${fs_used /}/${fs_size /}
${fs_bar 4 /}
${color 88C0D0}Network${color}
Down: ${downspeed eth0} $alignr Up: ${upspeed eth0}
]]
EOF

# Autostart conky
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/conky.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=conky
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Conky
Comment=System monitor
EOF
```

### 8. Polybar (Alternative to GNOME Shell)

For i3/sway users:

```bash
sudo pacman -S polybar

# Create Nord-themed config
mkdir -p ~/.config/polybar
# Download CachyOS-themed polybar config
curl -o ~/.config/polybar/config https://raw.githubusercontent.com/adi1090x/polybar-themes/master/simple/nord/config.ini
```

### 9. GNOME Extensions for Ricing

```bash
# Install Extension Manager
sudo pacman -S extension-manager

# Recommended extensions:
# - Dash to Dock (dock customization)
# - Blur my Shell (blur effects)
# - Just Perfection (GNOME tweaks)
# - Compiz alike magic lamp effect
# - Desktop Cube
# - Tiling Shell
```

Install via Extension Manager or:

```bash
yay -S gnome-shell-extension-dash-to-dock
yay -S gnome-shell-extension-blur-my-shell
```

### 10. Complete GTK4/libadwaita Theming

Orchis theme includes libadwaita support (already installed). For consistency:

```bash
# Force GTK4 apps to use Orchis
mkdir -p ~/.config/gtk-4.0
ln -sf /usr/share/themes/Orchis-Dark/gtk-4.0/gtk.css ~/.config/gtk-4.0/gtk.css
ln -sf /usr/share/themes/Orchis-Dark/gtk-4.0/gtk-dark.css ~/.config/gtk-4.0/gtk-dark.css
```

## CachyOS Performance Optimizations

### Enable GNOME Performance Mode

```bash
# Install power-profiles-daemon
sudo pacman -S power-profiles-daemon

# Set performance profile
powerprofilesctl set performance
```

### Reduce GNOME Animations for Snappiness

```bash
gsettings set org.gnome.desktop.interface enable-animations false
# Or reduce animation speed
gsettings set org.gnome.desktop.interface enable-animations true
gsettings set org.gnome.desktop.interface animation-duration 150  # ms
```

### Hardware-Accelerated Compositing

For NVIDIA RTX 4070 Ti:

```bash
# Already configured in your system, but verify:
nvidia-settings --query CurrentMetaMode
```

## Flatpak Application Theming

To theme Flatpak apps with Orchis:

```bash
# Grant access to themes
flatpak override --user --filesystem=xdg-data/themes
flatpak override --user --filesystem=xdg-data/icons

# Set GTK theme for all Flatpak apps
flatpak override --user --env=GTK_THEME=Orchis-Dark
```

## One-Command Rice Setup

```bash
#!/bin/bash
# CachyOS Orchis Rice Setup

# Install dependencies
sudo pacman -S --needed papirus-icon-theme gnome-tweaks extension-manager conky kitty

# Install AUR packages
yay -S --needed vimix-cursors gnome-shell-extension-user-theme gnome-shell-extension-dash-to-dock

# Configure GTK theme
gsettings set org.gnome.desktop.interface gtk-theme "Orchis-Dark"
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
gsettings set org.gnome.desktop.interface cursor-theme "Vimix-cursors"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface font-name "Cantarell 11"

# Enable GNOME Shell theme
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
gsettings set org.gnome.shell.extensions.user-theme name "Orchis-Dark"

# Configure Flatpak theming
flatpak override --user --filesystem=xdg-data/themes
flatpak override --user --filesystem=xdg-data/icons
flatpak override --user --env=GTK_THEME=Orchis-Dark

echo "CachyOS Orchis Rice setup complete! Restart GNOME Shell (Alt+F2, type 'r', Enter)"
```

## Screenshots and Verification

After applying the rice:

1. **Check GTK theme**:
   ```bash
   gsettings get org.gnome.desktop.interface gtk-theme
   ```

2. **Verify GNOME Shell theme**:
   ```bash
   gsettings get org.gnome.shell.extensions.user-theme name
   ```

3. **Take screenshot**:
   ```bash
   gnome-screenshot -f ~/Pictures/cachyos-orchis-rice.png
   ```

## Troubleshooting

### GTK2 Apps Not Themed

```bash
sudo pacman -S gtk-engine-murrine gnome-themes-extra
```

### Flatpak Apps Ignore Theme

```bash
# Reset and reapply
flatpak override --user --reset
flatpak override --user --filesystem=xdg-data/themes
flatpak override --user --env=GTK_THEME=Orchis-Dark
```

### GNOME Shell Theme Not Applied

```bash
# Re-enable User Themes extension
gnome-extensions disable user-theme@gnome-shell-extensions.gcampax.github.com
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com

# Restart GNOME Shell
# On Wayland: logout/login
# On X11: Alt+F2, type 'r', Enter
```

## Additional Resources

- **r/unixporn**: Reddit community for desktop ricing inspiration
- **CachyOS Forum**: https://discuss.cachyos.org/
- **GNOME-Look.org**: Browse themes, icons, and extensions
- **Dotfiles**: Share your configuration on GitHub

---

**Enjoy your beautifully riced CachyOS desktop with Orchis theme!**

**Per aspera ad astra** - Through hardships to the stars.
