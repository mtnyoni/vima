%global debug_package %{nil}

Name:           vima
Version:        %{vima_version}
Release:        %{vima_release}%{?dist}
Summary:        Fast graphical application launcher
License:        LicenseRef-Proprietary

Source0:        vima
Source1:        vima.desktop

Requires:       google-noto-sans-fonts
BuildRequires:  desktop-file-utils

%description
Vima is a keyboard-oriented graphical application launcher built with Odin,
SDL3, and SDL3_ttf.

%prep

%build

%install
install -Dm0755 %{SOURCE0} %{buildroot}%{_bindir}/vima
install -Dm0644 %{SOURCE1} %{buildroot}%{_datadir}/applications/vima.desktop

%check
desktop-file-validate %{SOURCE1}

%files
%{_bindir}/vima
%{_datadir}/applications/vima.desktop

%changelog
* Sun Aug 02 2026 Vima contributors <noreply@example.invalid> - %{vima_version}-%{vima_release}
- Initial RPM package
