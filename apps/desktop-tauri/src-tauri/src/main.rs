//! DeepSeek Harness desktop shell.
//!
//! The Rust core is only a native window around the Node-hosted `dsh web`
//! server: it spawns `node .../lib/bin.js web --port 0`, waits for the
//! `dsh web: http://127.0.0.1:<port>` readiness line, and loads that URL into
//! a WKWebView. The frontend keeps its existing HTTP/WebSocket transport
//! (same-origin), so no IPC bridge is needed.

use std::{
    io::{BufRead, BufReader},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
};
use semver::Version;
use tauri::path::BaseDirectory;
use tauri::{Manager, RunEvent, WebviewUrl, WebviewWindowBuilder};
use url::Url;

struct DshProcess {
    child: Mutex<Option<Child>>,
}

const MIN_22: Version = Version::new(22, 19, 0);
const MIN_24: Version = Version::new(24, 0, 0);

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let home_dir = std::env::var_os("HOME").map(PathBuf::from);

            // Tauri maps `..` in bundled resource paths to `_up_`; resolve()
            // applies that mapping, so these are the on-disk locations inside
            // `Contents/Resources/_up_/runtime/...`.
            let bundled_node =
                app.path().resolve("../runtime/node/bin/node", BaseDirectory::Resource)?;
            let bundled_bin = app.path().resolve(
                "../runtime/node_modules/@deepseek-ai/dsh/lib/bin.js",
                BaseDirectory::Resource,
            )?;

            let mut child = spawn_dsh(&bundled_node, &bundled_bin, home_dir.as_deref());
            let url = wait_for_url(&mut child)?;
            app.manage(DshProcess { child: Mutex::new(Some(child)) });

            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url.parse::<Url>()?))
                .title("DeepSeek Harness")
                .inner_size(1440.0, 900.0)
                .min_inner_size(960.0, 640.0)
                .build()?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let RunEvent::Exit = event {
                kill_dsh(app_handle);
            }
        });
}

/// Read a candidate node's version via `node -p process.versions.node`.
fn node_version(node: &Path) -> Option<Version> {
    let out = Command::new(node)
        .arg("-p")
        .arg("process.versions.node")
        .output()
        .ok()?;
    if !out.status.success() { return None; }
    Version::parse(String::from_utf8(out.stdout).ok()?.trim()).ok()
}

/// dsh `engines`: `^22.19.0 || >=24.0.0`.
fn is_supported(v: &Version) -> bool {
    (v.major == 22 && v >= &MIN_22) || v >= &MIN_24
}

/// Resolve the Node executable: bundled first (deterministic, self-contained),
/// then a fallback to PATH — but only after the same version gate. Fails loud
/// when neither path yields a supported runtime.
fn resolve_node(bundled_node: &Path) -> PathBuf {
    if bundled_node.exists() {
        match node_version(bundled_node) {
            Some(v) if is_supported(&v) => return bundled_node.to_path_buf(),
            Some(v) => eprintln!("[dsh] bundled node {v} unsupported; falling back to PATH"),
            None => eprintln!("[dsh] bundled node unreadable; falling back to PATH"),
        }
    } else {
        eprintln!("[dsh] bundled node missing; falling back to PATH");
    }
    let system = PathBuf::from("node");
    match node_version(&system) {
        Some(v) if is_supported(&v) => system,
        Some(v) => panic!(
            "no usable Node: system node {v} does not satisfy dsh engines (^22.19.0 || >=24.0.0)"
        ),
        None => panic!("no usable Node: bundled node missing/unsupported and no node on PATH"),
    }
}

fn spawn_dsh(
    bundled_node: &Path,
    bundled_bin: &Path,
    home_dir: Option<&Path>,
) -> Child {
    let node = resolve_node(bundled_node);
    if !bundled_bin.exists() {
        panic!(
            "missing bundled dsh bin at {} (run scripts/prepare-runtime.sh first)",
            bundled_bin.display()
        );
    }

    let mut cmd = Command::new(node);
    cmd.arg(bundled_bin)
        .arg("web")
        .arg("--no-open")
        .arg("--port")
        .arg("0")
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    if let Some(h) = home_dir {
        cmd.current_dir(h);
    }
    cmd.spawn().expect("failed to spawn dsh")
}

/// Block until dsh prints its readiness line, then hand stdout draining off to
/// a background thread so the pipe stays open (Node would otherwise hit EPIPE).
fn wait_for_url(child: &mut Child) -> Result<String, Box<dyn std::error::Error>> {
    let stdout = child.stdout.take().expect("dsh stdout");
    let mut lines = BufReader::new(stdout).lines();
    loop {
        let line = match lines.next() {
            Some(Ok(l)) => l,
            Some(Err(e)) => return Err(e.into()),
            None => return Err("dsh exited before printing its URL line".into()),
        };
        println!("[dsh] {line}");
        if let Some(rest) = line.strip_prefix("dsh web: ") {
            let url = rest.split(" (LAN:").next().unwrap_or(rest).trim().to_string();
            std::thread::spawn(move || {
                for l in lines {
                    if let Ok(l) = l { println!("[dsh] {l}"); }
                }
            });
            return Ok(url);
        }
    }
}

fn kill_dsh(app_handle: &tauri::AppHandle) {
    if let Some(state) = app_handle.try_state::<DshProcess>() {
        if let Ok(mut guard) = state.inner().child.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
            }
        }
    }
}
