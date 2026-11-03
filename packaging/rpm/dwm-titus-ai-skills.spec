Name:           dwm-titus-ai-skills
Version:        0.1.0
Release:        1%{?dist}
Summary:        AI agent skills for customizing and debugging dwm-titus
License:        MIT
URL:            https://github.com/ChrisTitusTech/dwm-titus
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

%description
Agent skills that teach AI coding agents (Codex, OpenCode, Gemini CLI and
others that read ~/.agents/skills) how dwm-titus is put together: where the
runtime configuration lives, which helpers own which settings, and how to
diagnose crashes, hung windows and broken desktop parts without guessing.

dwm-agent links these skills into each user's ~/.agents/skills on setup, and
prefers this system copy over the one in the dwm-titus data directory, so the
skills can be updated as a package, independently of the desktop.

%prep
%autosetup

%build

%check
# Every skill needs front matter whose name matches its directory.
for skill in skills/*/; do
    name=$(basename "$skill")
    test "$(sed -n 1p "$skill/SKILL.md")" = "---"
    grep -qx "name: $name" "$skill/SKILL.md"
    grep -q '^description: ' "$skill/SKILL.md"
done

%install
install -d %{buildroot}%{_datadir}/dwm-titus/agents/skills
cp -a skills/. %{buildroot}%{_datadir}/dwm-titus/agents/skills/

%files
%license LICENSE
%doc README.md
%dir %{_datadir}/dwm-titus
%dir %{_datadir}/dwm-titus/agents
%{_datadir}/dwm-titus/agents/skills/

%changelog
* Sun Oct 11 2026 Lef <me@lefteros.com> - 0.1.0-1
- First package: dwm-titus and dwm-titus-debug skills
