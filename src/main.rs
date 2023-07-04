use anyhow::{ensure, Context, Result};
use nix::unistd::{initgroups, setresgid, setresuid, Gid, Uid};
use sha2::{Digest, Sha512};
use std::fs::File;
use std::io::{BufReader, Read};
use std::os::unix::process::CommandExt;
use std::{ffi::CString, process::Command};
use users::{get_group_by_name, get_user_by_name, group_access_list};

/// A comma separated list of users for which to allow elevation of privileges using this utility.
/// Leave unset for an empty list.
/// Optional.
const ALLOWED_USERS: Option<&str> = option_env!("ELEWRAP_ALLOWED_USERS");
/// A comma separated list of groups for which to allow elevation of privileges using this utility.
/// Leave unset for an empty list.
/// Optional.
const ALLOWED_GROUPS: Option<&str> = option_env!("ELEWRAP_ALLOWED_GROUPS");
/// The target user to change to before executing the command.
/// Required.
const TARGET_USER: &str = env!("ELEWRAP_TARGET_USER");
/// The delimiter on which to split the target command.
/// Default: "\t"
const TARGET_COMMAND_DELIMITER: &str = match option_env!("ELEWRAP_TARGET_COMMAND_DELIMITER") {
    Some(x) => x,
    None => "\t",
};
/// The command to execute after changing to the target user. This must be an absolute path.
/// Required.
const TARGET_COMMAND: &[&str] =
    &const_str::split!(env!("ELEWRAP_TARGET_COMMAND"), TARGET_COMMAND_DELIMITER);
/// If set, authenticates the target command via its sha512 hash at runtime.
/// Optional.
const TARGET_COMMAND_SHA512: Option<&str> = option_env!("ELEWRAP_TARGET_COMMAND_SHA512");
/// Whether additional runtime arguments should be supplied to the executed command
/// Default: false
const PASS_RUNTIME_ARGUMENTS: bool = match option_env!("ELEWRAP_PASS_RUNTIME_ARGUMENTS") {
    Some(x) => const_str::equal!(x, "true") || const_str::equal!(x, "1"),
    None => false,
};

// The target command must have at least one component
static_assertions::const_assert!(!TARGET_COMMAND.is_empty());

/// Drop all privileges and change to the target user.
fn drop_privileges() -> Result<()> {
    let user =
        get_user_by_name(TARGET_USER).context(format!("Invalid target user: {}", TARGET_USER))?;

    let target_uid: Uid = user.uid().into();
    let target_gid: Gid = user.primary_group_id().into();

    let setgroups_res = unsafe { libc::setgroups(0, std::ptr::null()) };
    ensure!(setgroups_res == 0, "Failed to drop groups with setgroups!");

    let cstr_target_user = CString::new(TARGET_USER.as_bytes())?;
    initgroups(&cstr_target_user, target_gid)?;
    setresgid(target_gid, target_gid, target_gid)?;
    setresuid(target_uid, target_uid, target_uid)?;
    Ok(())
}

/// Authorizes the given caller.
fn authorize(caller_uid: Uid, caller_gids: &[u32]) -> Result<()> {
    let is_allowed_user = || {
        ALLOWED_USERS.map_or(false, |xs| {
            xs.split(',')
                .any(|x| get_user_by_name(x).map_or(false, |x| x.uid() == caller_uid.as_raw()))
        })
    };

    let has_allowed_group = || {
        ALLOWED_GROUPS.map_or(false, |xs| {
            xs.split(',')
                .any(|x| get_group_by_name(x).map_or(false, |x| caller_gids.contains(&x.gid())))
        })
    };

    ensure!(is_allowed_user() || has_allowed_group(), "Unauthorized.");
    Ok(())
}

fn sha512_digest(path: &str) -> Result<String> {
    let input = File::open(path)?;
    let mut reader = BufReader::new(input);
    let mut hasher = Sha512::new();
    let mut buffer = [0; 4096];
    loop {
        let count = reader.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

fn main() -> Result<()> {
    // The target command must be an absolute path
    // XXX: this can be done statically, but not in ed 2021 without going unstable
    ensure!(
        TARGET_COMMAND[0].starts_with('/'),
        "The target command must use an absolute path"
    );

    // Remember the calling uid and gid for checking access later
    let caller_uid = Uid::current();
    let mut caller_gids: Vec<_> = group_access_list()?.iter().map(|x| x.gid()).collect();
    caller_gids.push(Gid::current().as_raw());

    // If the sha512 was baked-in, ensure that the called program has the correct hash.
    // Do that before dropping privileges, otherwise we might not be able to read the file.
    if let Some(expected_digest) = TARGET_COMMAND_SHA512 {
        let hex_digest = sha512_digest(TARGET_COMMAND[0])?;
        ensure!(
            hex_digest == expected_digest,
            "Target executable failed sha512 digest verification. Bailing."
        );
    }

    // Drop privileges as soon as possible
    drop_privileges()?;
    // TODO clear environment

    // Authorization the calling user
    authorize(caller_uid, &caller_gids)?;

    // Execute command
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let mut cmd = Command::new(TARGET_COMMAND[0]);
    cmd.args(&TARGET_COMMAND[1..]);
    if PASS_RUNTIME_ARGUMENTS {
        cmd.args(&args);
    }
    Err(cmd.exec().into())
}
