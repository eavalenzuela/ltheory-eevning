//! The Windows .exe's own icon: with `LT_WINDOWS_ICON` naming an .ico (`script/publish` sets it when the repository
//! has one), a Windows build compiles it in as the program's icon resource with MinGW's `windres` (`WINDRES` to name
//! another). Other builds: nothing.

use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=LT_WINDOWS_ICON");
    println!("cargo:rerun-if-env-changed=WINDRES");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let Ok(ico) = std::env::var("LT_WINDOWS_ICON") else { return };
    if !Path::new(&ico).is_file() {
        println!("cargo:warning=LT_WINDOWS_ICON {ico}: no such file (the .exe keeps no icon)");
        return;
    }
    println!("cargo:rerun-if-changed={ico}");
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let rc = out.join("icon.rc");
    std::fs::write(&rc, format!("1 ICON \"{}\"\n", ico.replace('\\', "/"))).expect("icon.rc");
    let obj = out.join("icon.o");
    let windres = std::env::var("WINDRES").unwrap_or_else(|_| "x86_64-w64-mingw32-windres".into());
    match Command::new(&windres).arg(&rc).args(["-O", "coff", "-o"]).arg(&obj).status() {
        Ok(s) if s.success() => println!("cargo:rustc-link-arg-bins={}", obj.display()),
        r => println!("cargo:warning={windres}: {r:?} (the .exe keeps no icon)"),
    }
}
