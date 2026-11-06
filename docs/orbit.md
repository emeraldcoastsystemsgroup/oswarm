# OSHAL Orbit computer setup

Swarm runs your server. Orbit connects a computer to that server. Install Orbit
on every computer you want to control, then open it and complete Computer setup.

1. Enter your Swarm workspace address. For a server on this computer, use the
   address the Swarm installer printed.
2. Choose **Open workspace and sign in** and sign in with your own account.
3. Choose **Allow control of this computer** when you want to allow its tools.
4. Choose **Connect browser** and follow the instructions shown there. Once the
   production Chrome listing is available, this opens its installation page;
   approve **Add extension** in Chrome or Edge, then return to Orbit. A supported
   Debian installation can already have the bundled browser integration enabled.
5. Orbit checks the connection automatically. **Finish setup** becomes available
   after sign-in, control, and browser checks pass. You can explicitly choose
   **Continue without browser controls** and return to setup later.

Orbit 0.7.1 includes the native helper and add-on. Its Chrome Web Store item
(`aklbpgcigmeidmaiebpohcmnjioihecb`) is assigned and submitted, and the listing
is waiting for Google's review. Until that listing is public, Connect browser
explains that publication is pending; do not describe 0.7.1 as a completed
production browser installation.

Browser installation requires the browser’s confirmation because the add-on can
read requested pages and perform actions in your signed-in browser. Automatic
pairing uses the bundled local helper; the production flow uses no copied code
or developer mode. See [Orbit browser privacy](https://oshal.ai/privacy/#orbit-browser).

With your own computer unlocked and signed in, Orbit can perform supported
browser clicks, typing, navigation, and ordinary Continue or existing-account
sign-in actions requested through your workspace. Local and cloud models use
the same computer permissions. Disable computer control in Orbit to refuse
further commands.

## Server controls

Open **Server controls** in Orbit’s menu. Under **Run on**, choose **This
computer** or **Another computer over SSH**. Select the Docker installation or
supported Linux user service and enter its installation folder when needed.
Choose **Status**, **Start**, **Stop**, **Restart**, or **Recent logs**.

SSH uses this computer’s existing keys and known hosts, with noninteractive
authentication. Establish ordinary SSH access before using these controls.
The controls run independently of the Swarm server, allowing Start when that
server is stopped. Kubernetes management currently uses the npm commands in
the [Kubernetes guide](../install/kubernetes/README.md).

## Verification scope

The 0.7.1 Windows x64 installer passed actual installation, first-run setup,
Chrome/Edge native-host registration for the assigned store item, native
messaging, and uninstall on a disposable Windows runner. The Linux x64 and ARM64
Debian packages and AppImages passed installed first-run, bundled native helper
and browser host registration checks on disposable Linux runners, and both
Debian packages uninstalled cleanly. Those checks do not establish authenticated
physical desktop control, Chrome Web Store installation, or live SSH control;
those remain separate acceptance work.
