export const navigation = [
  { href: "/install.html", label: "Installation", index: "01", group: "Start" },
  { href: "/getting-started.html", label: "Getting Started", index: "02", group: "Start" },
  { href: "/development-progress.html", label: "Development Progress", index: "03", group: "Project" },
  { href: "/keybinds.html", label: "Keybindings", index: "04", group: "Use" },
  { href: "/configuration.html", label: "Configuration", index: "05", group: "Customize" },
  { href: "/theming.html", label: "Theming", index: "06", group: "Customize" },
  { href: "/control-center.html", label: "Control Center", index: "07", group: "Use" },
  { href: "/settings.html", label: "Settings", index: "08", group: "Use" },
  { href: "/patches.html", label: "How It Works", index: "09", group: "Project" },
  { href: "/troubleshooting.html", label: "Troubleshooting", index: "10", group: "Help" }
] as const;

export const projectLinks = [
  { href: "https://github.com/ChrisTitusTech/dwm-titus", label: "GitHub" },
  { href: "https://github.com/ChrisTitusTech/dwm-titus/releases/latest", label: "Latest release" }
] as const;
