package main

Application :: struct {
	name:        cstring,
	executable:  cstring,
	icon:        cstring,
	desktop_id:  cstring,
	description: cstring,
	keywords:    cstring,
}

DUMMY_APPLICATIONS :: [?]Application {
	{"Firefox", "firefox", "firefox", "firefox.desktop", "Browse the web", "browser web internet"},
	{"Konsole", "konsole", "utilities-terminal", "org.kde.konsole.desktop", "Open a terminal", "terminal shell command"},
	{"Dolphin", "dolphin", "system-file-manager", "org.kde.dolphin.desktop", "Browse files and folders", "files folders manager"},
	{"Kate", "kate", "kate", "org.kde.kate.desktop", "Edit text and source code", "editor text code"},
	{"System Settings", "systemsettings", "preferences-system", "systemsettings.desktop", "Configure KDE Plasma", "settings preferences plasma"},
	{"Discover", "plasma-discover", "plasmadiscover", "org.kde.discover.desktop", "Install and update software", "software apps packages"},
	{"Spectacle", "spectacle", "spectacle", "org.kde.spectacle.desktop", "Capture screenshots", "screenshot capture screen"},
	{"Okular", "okular", "okular", "org.kde.okular.desktop", "Read documents and PDFs", "pdf document reader"},
	{"Gwenview", "gwenview", "gwenview", "org.kde.gwenview.desktop", "View and organize images", "image photo viewer"},
	{"Elisa", "elisa", "elisa", "org.kde.elisa.desktop", "Listen to music", "music audio player"},
	{"KCalc", "kcalc", "accessories-calculator", "org.kde.kcalc.desktop", "Perform calculations", "calculator math"},
	{"KWrite", "kwrite", "kwrite", "org.kde.kwrite.desktop", "Edit plain text", "editor text notes"},
	{"Ark", "ark", "utilities-file-archiver", "org.kde.ark.desktop", "Manage compressed archives", "archive zip tar"},
	{"KRunner", "krunner", "system-run", "org.kde.krunner.desktop", "Search and run commands", "launcher search command"},
	{"LibreOffice Writer", "libreoffice --writer", "libreoffice-writer", "libreoffice-writer.desktop", "Create and edit documents", "office document writer"},
	{"VLC", "vlc", "vlc", "vlc.desktop", "Play videos and music", "video media audio player"},
	{"Discord", "discord", "discord", "discord.desktop", "Chat with communities", "chat voice messaging"},
	{"Steam", "steam", "steam", "steam.desktop", "Browse and play games", "games store library"},
	{"Visual Studio Code", "code", "visual-studio-code", "code.desktop", "Edit and debug source code", "editor development code"},
	{"Obsidian", "obsidian", "obsidian", "obsidian.desktop", "Write and connect notes", "notes markdown knowledge"},
}
