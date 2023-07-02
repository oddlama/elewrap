use anyhow::{ensure, Context, Result};
use nix::unistd::{initgroups, setresgid, setresuid, Gid, Uid};
use std::os::unix::process::CommandExt;
use std::{ffi::CString, process::Command};

use users::{get_group_by_name, get_user_by_name, group_access_list};

/// Drop all privileges and become the given user.
fn drop_privileges(target_user: &str) -> Result<()> {
    let user =
        get_user_by_name(target_user).context(format!("Invalid target user: {}", target_user))?;

    let target_uid: Uid = user.uid().into();
    let target_gid: Gid = user.primary_group_id().into();

    let setgroups_res = unsafe { libc::setgroups(0, std::ptr::null()) };
    ensure!(setgroups_res == 0, "Failed to drop groups with setgroups!");

    let cstr_target_user = CString::new(target_user.as_bytes())?;
    initgroups(&cstr_target_user, target_gid)?;
    setresgid(target_gid, target_gid, target_gid)?;
    setresuid(target_uid, target_uid, target_uid)?;
    Ok(())
}

fn authorize(caller_uid: Uid, caller_gids: &[u32]) -> Result<()> {
    let allowed_users = ["root", "0"];
    let allowed_groups = ["root", "0"];

    let is_allowed_user = || {
        allowed_users
            .iter()
            .any(|x| get_user_by_name(x).map_or(false, |x| x.uid() == caller_uid.as_raw()))
    };

    let has_allowed_group = || {
        allowed_groups
            .iter()
            .any(|x| get_group_by_name(x).map_or(false, |x| caller_gids.contains(&x.gid())))
    };

    ensure!(is_allowed_user() || has_allowed_group(), "Unauthorized.");
    Ok(())
}

fn main() -> Result<()> {
    let target_user = "nobody";

    // Remember the calling uid and gid for checking access later
    let caller_uid = Uid::current();
    let mut caller_gids: Vec<_> = group_access_list()?.iter().map(|x| x.gid()).collect();
    caller_gids.push(Gid::current().as_raw());

    // Drop privileges as soon as possible
    drop_privileges(target_user)?;

    // Authorization the calling user
    authorize(caller_uid, &caller_gids)?;

    // Execute command
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    Err(Command::new("id").args(&args).exec().into())
}
