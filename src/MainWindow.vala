/*-
 * Copyright (c) 2017-2017 Artem Anufrij <artem.anufrij@live.de>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The Noise authors hereby grant permission for non-GPL compatible
 * GStreamer plugins to be used and distributed together with GStreamer
 * and Noise. This permission is above and beyond the permissions granted
 * by the GPL license by which Noise is covered. If you modify this code
 * you may extend this exception to your version of the code, but you are not
 * obligated to do so. If you do not wish to do so, delete this exception
 * statement from your version.
 *
 * Authored by: Artem Anufrij <artem.anufrij@live.de>
 */

namespace PlayMyMusic {
    public class MainWindow : Gtk.Window {
        PlayMyMusic.Services.LibraryManager library_manager;
        PlayMyMusic.Settings settings;

        //CONTROLS
        Gtk.HeaderBar headerbar;
        Gtk.SearchEntry search_entry;
        Gtk.Spinner spinner;
        Gtk.Button play_button;
        Gtk.Button next_button;
        Gtk.Button previous_button;
        Gtk.MenuItem menu_item_rescan;
        Gtk.MenuItem menu_item_reset;
        Gtk.Image icon_play;
        Gtk.Image icon_pause;
        Gtk.Stack content;

        Gtk.Widget audio_cd_widget;
        Gtk.Image artist_button;
        Gtk.Image playlist_button;

        Granite.Widgets.ModeButton view_mode;

        Widgets.Views.AlbumsView albums_view;
        Widgets.Views.ArtistsView artists_view;
        Widgets.Views.RadiosView radios_view;
        Widgets.Views.PlaylistsView playlists_view;
        Widgets.Views.AudioCDView audio_cd_view;

        Widgets.TrackTimeLine timeline;

        Notification desktop_notification;

        bool send_desktop_notification = true;
        uint adjust_timer = 0;

        construct {
            settings = PlayMyMusic.Settings.get_default ();

            library_manager = PlayMyMusic.Services.LibraryManager.instance;
            library_manager.tag_discover_started.connect (() => {
                Idle.add (() => {
                    spinner.active = true;
                    menu_item_rescan.sensitive = false;
                    menu_item_reset.sensitive = false;
                });
            });
            library_manager.tag_discover_finished.connect (() => {
                Idle.add (() => {
                    spinner.active = false;
                    menu_item_rescan.sensitive = true;
                    menu_item_reset.sensitive = true;
                });
            });
            library_manager.added_new_artist.connect (() => {
                if (!artist_button.sensitive) {
                    artist_button.sensitive = true;
                    playlist_button.sensitive = true;
                }
            });

            library_manager.player_state_changed.connect ((state) => {
                play_button.sensitive = true;
                if (state == Gst.State.PLAYING) {
                    play_button.image = icon_pause;
                    play_button.tooltip_text = _("Pause");
                    if (library_manager.player.current_track != null) {
                        timeline.set_playing_track (library_manager.player.current_track);
                        headerbar.set_custom_title (timeline);
                        send_notification (library_manager.player.current_track);
                        previous_button.sensitive = true;
                        next_button.sensitive = true;
                    } else if (library_manager.player.current_file != null) {
                        timeline.set_playing_file (library_manager.player.current_file);
                        headerbar.set_custom_title (timeline);
                        previous_button.sensitive = false;
                        next_button.sensitive = false;
                    } else if (library_manager.player.current_radio != null) {
                        headerbar.title = library_manager.player.current_radio.title;
                        previous_button.sensitive = false;
                        next_button.sensitive = false;
                    }
                } else {
                    if (state == Gst.State.PAUSED) {
                        timeline.pause_playing ();
                    } else {
                        timeline.stop_playing ();
                        headerbar.set_custom_title (null);
                        headerbar.title = _("Play My Music");
                    }
                    play_button.image = icon_play;
                    play_button.tooltip_text = _("Play");
                }
            });

            library_manager.audio_cd_connected.connect ((audio_cd) => {
                audio_cd_view.show_audio_cd (audio_cd);
                audio_cd_widget.show ();
                view_mode.set_active (4);
            });

            library_manager.audio_cd_disconnected.connect ((volume) => {
                if (audio_cd_view.current_audio_cd != null && audio_cd_view.current_audio_cd.volume == volume) {
                    if (library_manager.player.play_mode == PlayMyMusic.Services.PlayMode.AUDIO_CD) {
                        library_manager.player.reset_playing ();
                    }
                    audio_cd_view.reset ();
                    audio_cd_widget.hide ();
                    show_playing_view ();
                }
            });
        }

        public MainWindow () {
            load_settings ();
            this.window_position = Gtk.WindowPosition.CENTER;
            build_ui ();

            load_content_from_database.begin ((obj, res) => {
                albums_view.activate_by_id (settings.last_album_id);
                if (settings.look_for_new_files) {
                    library_manager.scan_local_library (settings.library_location);
                }
                load_last_played_track ();
            });

            this.configure_event.connect ((event) => {
                settings.window_width = event.width;
                settings.window_height = event.height;
                artists_view.load_background ();
                audio_cd_view.load_background ();

                adjust_background_images ();
                return false;
            });

            this.delete_event.connect (() => {
                if (settings.play_in_background && library_manager.player.get_state () == Gst.State.PLAYING) {
                    this.hide_on_delete ();
                    return true;
                }
                return false;
            });

            this.destroy.connect (() => {
                save_settings ();
                library_manager.player.stop ();
            });

            Granite.Widgets.Utils.set_theming_for_screen (
                this.get_screen (),
                """
                    .artist-title {
                        color: #fff;
                        text-shadow: 0px 1px 2px alpha (#000, 1);
                    }
                    .artist-sub-title {
                        color: #fff;
                        text-shadow: 0px 1px 2px alpha (#000, 1);
                    }
                    .playlist-tracks {
                        background: transparent;
                    }
                    .mode_button_split {
                        border-left-width: 1px;
                    }
                """,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        public void build_ui () {
            // CONTENT
            content = new Gtk.Stack ();

            headerbar = new Gtk.HeaderBar ();
            headerbar.title = _("Play My Music");
            headerbar.show_close_button = true;
            this.set_titlebar (headerbar);

            // PLAY BUTTONS
            icon_play = new Gtk.Image.from_icon_name ("media-playback-start-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            icon_pause = new Gtk.Image.from_icon_name ("media-playback-pause-symbolic", Gtk.IconSize.LARGE_TOOLBAR);

            previous_button = new Gtk.Button.from_icon_name ("media-skip-backward-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            previous_button.tooltip_text = _("Previous");
            previous_button.sensitive = false;
            previous_button.clicked.connect (() => {
                library_manager.player.prev ();
            });

            play_button = new Gtk.Button ();
            play_button.image = icon_play;
            play_button.tooltip_text = _("Play");
            play_button.sensitive = false;
            play_button.clicked.connect (() => {
                play ();
            });

            next_button = new Gtk.Button.from_icon_name ("media-skip-forward-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            next_button.tooltip_text = _("Next");
            next_button.sensitive = false;
            next_button.clicked.connect (() => {
                library_manager.player.next ();
            });

            headerbar.pack_start (previous_button);
            headerbar.pack_start (play_button);
            headerbar.pack_start (next_button);

            build_mode_buttons ();

            // TIMELINE
            timeline = new Widgets.TrackTimeLine ();
            timeline.goto_current_track.connect ((track) => {
                if (track != null) {
                    switch (library_manager.player.play_mode) {
                        case PlayMyMusic.Services.PlayMode.ALBUM:
                            view_mode.set_active (0);
                            albums_view.activate_by_track (track);
                            break;
                        case PlayMyMusic.Services.PlayMode.ARTIST:
                            view_mode.set_active (1);
                            artists_view.activate_by_track (track);
                            break;
                        case PlayMyMusic.Services.PlayMode.PLAYLIST:
                            view_mode.set_active (2);
                            playlists_view.activate_by_track (track);
                            break;
                        case PlayMyMusic.Services.PlayMode.AUDIO_CD:
                            view_mode.set_active (4);
                            break;
                    }
                }
            });

            // SETTINGS MENU
            var app_menu = new Gtk.MenuButton ();
            app_menu.set_image (new Gtk.Image.from_icon_name ("open-menu", Gtk.IconSize.LARGE_TOOLBAR));

            var settings_menu = new Gtk.Menu ();

            var menu_item_library = new Gtk.MenuItem.with_label(_("Change Music Folder…"));
            menu_item_library.activate.connect (() => {
                var folder = library_manager.choose_folder ();
                if(folder != null) {
                    settings.library_location = folder;
                    library_manager.scan_local_library (folder);
                }
            });

            var menu_item_import = new Gtk.MenuItem.with_label (_("Import Music…"));
            menu_item_import.activate.connect (() => {
                var folder = library_manager.choose_folder ();
                if(folder != null) {
                    library_manager.scan_local_library (folder);
                }
            });

            menu_item_reset = new Gtk.MenuItem.with_label (_("Reset all views"));
            menu_item_reset.activate.connect (() => {
                reset_all_views ();
                library_manager.reset_library ();
            });

            menu_item_rescan = new Gtk.MenuItem.with_label (_("Rescan Library"));
            menu_item_rescan.activate.connect (() => {
                reset_all_views ();
                library_manager.rescan_library ();
            });

            var menu_item_preferences = new Gtk.MenuItem.with_label (_("Preferences"));
            menu_item_preferences.activate.connect (() => {
                var preferences = new Dialogs.Preferences (this);
                preferences.run ();
            });

            settings_menu.append (menu_item_library);
            settings_menu.append (menu_item_import);
            settings_menu.append (new Gtk.SeparatorMenuItem ());
            settings_menu.append (menu_item_rescan);
            settings_menu.append (menu_item_reset);
            settings_menu.append (new Gtk.SeparatorMenuItem ());
            settings_menu.append (menu_item_preferences);
            settings_menu.show_all ();

            app_menu.popup = settings_menu;
            headerbar.pack_end (app_menu);

            // SEARCH ENTRY
            search_entry = new Gtk.SearchEntry ();
            search_entry.placeholder_text = _("Search Music");
            search_entry.margin_right = 5;
            search_entry.search_changed.connect (() => {
                switch (view_mode.selected) {
                    case 1:
                        artists_view.filter = search_entry.text;
                        break;
                    case 2:
                        playlists_view.filter = search_entry.text;
                        break;
                    case 3:
                        radios_view.filter = search_entry.text;
                        break;
                    case 4:
                        audio_cd_view.filter = search_entry.text;
                        break;
                    default:
                        albums_view.filter = search_entry.text;
                        break;
                }
            });
            headerbar.pack_end (search_entry);

            // SPINNER
            spinner = new Gtk.Spinner ();
            headerbar.pack_end (spinner);

            albums_view = new Widgets.Views.AlbumsView ();
            albums_view.album_selected.connect (() => {
                previous_button.sensitive = true;
                play_button.sensitive = true;
                next_button.sensitive = true;
            });

            artists_view = new Widgets.Views.ArtistsView ();
            artists_view.artist_selected.connect (() => {
                previous_button.sensitive = true;
                play_button.sensitive = true;
                next_button.sensitive = true;
            });

            playlists_view = new Widgets.Views.PlaylistsView ();

            radios_view = new Widgets.Views.RadiosView ();

            audio_cd_view = new Widgets.Views.AudioCDView ();

            content.add_named (albums_view, "albums");
            content.add_named (artists_view, "artists");
            content.add_named (playlists_view, "playlists");
            content.add_named (radios_view, "radios");
            content.add_named (audio_cd_view, "audiocd");

            this.add (content);
            this.show_all ();

            audio_cd_widget.hide ();
            albums_view.hide_album_details ();

            library_manager.device_manager.init ();

            radios_view.unselect_all ();
            search_entry.grab_focus ();
        }

        private void build_mode_buttons () {
            // VIEW BUTTONS
            view_mode = new Granite.Widgets.ModeButton ();
            view_mode.homogeneous = false;
            view_mode.valign = Gtk.Align.CENTER;
            view_mode.margin_left = 12;

            var album_button = new Gtk.Image.from_icon_name ("view-grid-symbolic", Gtk.IconSize.BUTTON);
            album_button.tooltip_text = _("Albums");
            view_mode.append (album_button);

            artist_button = new Gtk.Image.from_icon_name ("avatar-default-symbolic", Gtk.IconSize.BUTTON);
            artist_button.tooltip_text = _("Artists");
            view_mode.append (artist_button);
            artist_button.sensitive = library_manager.artists.length () > 0;

            playlist_button = new Gtk.Image.from_icon_name ("view-list-compact-symbolic", Gtk.IconSize.BUTTON);
            playlist_button.tooltip_text = _("Playlists");
            view_mode.append (playlist_button);
            playlist_button.sensitive = library_manager.artists.length () > 0;

            var radio_button = new Gtk.Image.from_icon_name ("network-cellular-connected-symbolic", Gtk.IconSize.BUTTON);
            radio_button.tooltip_text = _("Radio Stations");
            view_mode.append (radio_button);
            var wid = view_mode.get_children ().last ().data;
            wid.margin_left = 4;
            wid.get_style_context ().add_class ("mode_button_split");

            var audio_cd_button = new Gtk.Image.from_icon_name ("media-optical-cd-audio-symbolic", Gtk.IconSize.BUTTON);
            audio_cd_button.tooltip_text = _("Audio CD");
            view_mode.append (audio_cd_button);
            audio_cd_widget = view_mode.get_children ().last ().data;

            view_mode.mode_changed.connect (() => {
                switch (view_mode.selected) {
                    case 1:
                        if (artist_button.sensitive) {
                            content.set_visible_child_name ("artists");
                            search_entry.text = artists_view.filter;
                            adjust_background_images ();
                        } else {
                            view_mode.set_active (0);
                        }
                        break;
                    case 2:
                        if (playlist_button.sensitive) {
                            if (library_manager.player.play_mode != PlayMyMusic.Services.PlayMode.PLAYLIST || playlists_view.filter != "") {
                                search_entry.grab_focus ();
                            }
                            content.set_visible_child_name ("playlists");
                            search_entry.text = playlists_view.filter;
                        } else {
                            view_mode.set_active (0);
                        }
                        break;
                    case 3:
                        if (library_manager.player.current_radio == null || radios_view.filter != "") {
                            search_entry.grab_focus ();
                        }
                        content.set_visible_child_name ("radios");
                        search_entry.text = radios_view.filter;
                        break;
                    case 4:
                        if (library_manager.player.play_mode != PlayMyMusic.Services.PlayMode.AUDIO_CD || audio_cd_view.filter != "") {
                            search_entry.grab_focus ();
                        }
                        previous_button.sensitive = true;
                        play_button.sensitive = true;
                        next_button.sensitive = true;
                        content.set_visible_child_name ("audiocd");
                        search_entry.text = audio_cd_view.filter;
                        adjust_background_images ();
                        break;
                    default:
                        content.set_visible_child_name ("albums");
                        search_entry.text = albums_view.filter;
                        break;
                }
            });
            headerbar.pack_start (view_mode);
        }

        private void send_notification (Objects.Track track) {
            if (!is_active && send_desktop_notification) {
                if (desktop_notification == null) {
                    desktop_notification = new Notification ("");
                }
                desktop_notification.set_title (track.title);
                if (library_manager.player.play_mode == PlayMyMusic.Services.PlayMode.AUDIO_CD) {
                    desktop_notification.set_body (_("<b>%s</b> by <b>%s</b>").printf (track.audio_cd.title, track.audio_cd.artist));
                    try {
                        var icon = GLib.Icon.new_for_string (track.audio_cd.cover_path);
                        desktop_notification.set_icon (icon);
                    } catch (Error err) {
                        warning (err.message);
                    }
                } else {
                    desktop_notification.set_body (_("<b>%s</b> by <b>%s</b>").printf (track.album.title, track.album.artist.name));
                    try {
                        var icon = GLib.Icon.new_for_string (track.album.cover_path);
                        desktop_notification.set_icon (icon);
                    } catch (Error err) {
                        warning (err.message);
                    }
                }
                this.application.send_notification (PlayMyMusicApp.instance.application_id, desktop_notification);
            }
        }

        private void adjust_background_images () {
            if (adjust_timer != 0) {
                Source.remove (adjust_timer);
                adjust_timer = 0;
            }
            adjust_timer = GLib.Timeout.add (100, () => {
                artists_view.load_background ();
                audio_cd_view.load_background ();
                Source.remove (adjust_timer);
                adjust_timer = 0;
                return false;
            });
        }

        private async void load_content_from_database () {
            foreach (var artist in library_manager.artists) {
                artists_view.add_artist (artist);
                foreach (var album in artist.albums) {
                    albums_view.add_album (album);
                }
            }
        }

        private void reset_all_views () {
            settings.last_artist_id = 0;
            settings.last_album_id = 0;
            view_mode.set_active (0);
            artist_button.sensitive = false;
            playlist_button.sensitive = false;
            albums_view.reset ();
            artists_view.reset ();
            radios_view.reset ();
        }

        public void play () {
            send_desktop_notification = false;
            if (library_manager.player.current_track != null || library_manager.player.current_radio != null || library_manager.player.current_file != null) {
                library_manager.player.toggle_playing ();
            } else {
                switch (view_mode.selected) {
                    case 0:
                        albums_view.play_selected_album ();
                        break;
                    case 1:
                        artists_view.play_selected_artist ();
                        break;
                    case 4:
                        audio_cd_view.play_audio_cd ();
                        break;
                }
            }
            send_desktop_notification = true;
        }

        private void show_playing_view () {
            var current_state = library_manager.player.get_state ();
            if (current_state == Gst.State.PLAYING || current_state == Gst.State.PAUSED){
                switch (library_manager.player.play_mode) {
                    case PlayMyMusic.Services.PlayMode.ALBUM:
                        view_mode.set_active (0);
                        break;
                    case PlayMyMusic.Services.PlayMode.ARTIST:
                        view_mode.set_active (1);
                        break;
                    case PlayMyMusic.Services.PlayMode.PLAYLIST:
                        view_mode.set_active (2);
                        break;
                    case PlayMyMusic.Services.PlayMode.RADIO:
                        view_mode.set_active (3);
                        break;
                }
            } else {
                view_mode.set_active (0);
            }
        }

        public void next () {
            send_desktop_notification = false;
            library_manager.player.next ();
            send_desktop_notification = true;
        }

        public void prev () {
            send_desktop_notification = false;
            library_manager.player.prev ();
            send_desktop_notification = true;
        }

        public void open_file (File file) {
            if (file.get_uri ().has_prefix ("cdda://")) {
                audio_cd_view.open_file (file);
            } else if (!albums_view.open_file (file.get_path ())) {
                library_manager.player.set_file (file);
            }
        }

        private void load_last_played_track () {
            switch (settings.track_source) {
                case "album":
                    view_mode.set_active (0);
                    var album = albums_view.activate_by_id (settings.last_album_id);
                    if (album != null) {
                        var track = album.get_track_by_id (settings.last_track_id);
                        if (track != null) {
                            library_manager.player.load_track (track, PlayMyMusic.Services.PlayMode.ALBUM);
                        }
                    }
                    break;
                case "artist":
                    view_mode.set_active (1);
                    var artist = artists_view.activate_by_id (settings.last_artist_id);
                    if (artist != null) {
                        var track = artist.get_track_by_id (settings.last_track_id);
                        if (track != null) {
                            library_manager.player.load_track (track, PlayMyMusic.Services.PlayMode.ARTIST);
                        }
                    }
                    break;
                case "playlist":
                    view_mode.set_active (2);
                    var playlist = playlists_view.activate_by_id (settings.last_playlist_id);
                    if (playlist != null) {
                        var track = playlist.get_track_by_id (settings.last_track_id);
                        if (track != null) {
                            library_manager.player.load_track (track, PlayMyMusic.Services.PlayMode.PLAYLIST);
                        }
                    }
                    break;

                default:
                    if (settings.view_index != 4 || audio_cd_view.current_audio_cd != null) {
                        view_mode.set_active (settings.view_index);
                    } else {
                        view_mode.set_active (0);
                    }
                    break;
            }
        }

        private void load_settings () {
            if (settings.window_maximized) {
                this.maximize ();
                this.set_default_size (1024, 720);
            } else {
                this.set_default_size (settings.window_width, settings.window_height);
            }
        }

        private void save_settings () {
            settings.window_maximized = this.is_maximized;
            settings.view_index = view_mode.selected;
            var current_track = library_manager.player.current_track;

            if (current_track != null && (library_manager.player.play_mode == PlayMyMusic.Services.PlayMode.ALBUM
                || library_manager.player.play_mode == PlayMyMusic.Services.PlayMode.ARTIST
                || library_manager.player.play_mode == PlayMyMusic.Services.PlayMode.PLAYLIST)) {
                settings.last_track_id = library_manager.player.current_track.ID;
                settings.track_progress = library_manager.player.get_position_progress ();
                switch (library_manager.player.play_mode) {
                    case PlayMyMusic.Services.PlayMode.ALBUM:
                        settings.last_album_id = current_track.album.ID;
                        settings.track_source = "album";
                        break;
                    case PlayMyMusic.Services.PlayMode.ARTIST:
                        settings.last_artist_id = current_track.album.artist.ID;
                        settings.track_source = "artist";
                        break;
                    case PlayMyMusic.Services.PlayMode.PLAYLIST:
                        settings.last_playlist_id = current_track.playlist.ID;
                        settings.track_source = "playlist";
                        break;
                }
            } else {
                settings.last_track_id = 0;
                settings.track_progress = 0;
                settings.track_source = "";
            }
        }
    }
}
