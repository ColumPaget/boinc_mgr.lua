SYNOPSIS
=========

boinc_mgr.lua is a menu-driven text-mode lua program for managing the boinc client app. It requires libUseful (at least version 4.0) and libUseful-lua (at least version 2.0) to be installed. boinc_mgr.lua can start and stop the boinc client app on local host, can join, attach, and detach from projects, and can start/stop tasks. It can also attach to boinc over tcp, and over tcp-over-ssh.

USAGE
=====
```
boinc_mgr.lua [host] [-key gui-key] [-user username] [-email email-address] [-pass password] [-save]

host  -  host to connect to. e.g. "tcp:192.168.2.1" or "ssh:myserver"

-key [gui-key]    This supplies the gui-key for a boinc process. This is needed for most control operations.
                  This key is normally found in the file "gui_rpc_auth.cfg" in whatever directory the boinc
                  process is running in.
 
-save             save the gui-key.

-acct_mgr [url]   Set account manager. This requires -user and -pass for the account manager login.

-user  [name]     Username. Needed for creating/joining project accounts and other management tasks.
-email [email]    email address. Needed for creating/joining project accounts
-pass  [passwd]   password. Needed for creating/joining project accounts and other management tasks.

```

Assuming you've used the same user, email and pass for all projects, the user, email, and pass can be set within the program itself, so that they don't need to be passed on the command-line every time. The gui-key can be saved on a per-host basis by using the "-save" option. This will save the key for the current host in "~/.boinc/keys.txt", allowing multiple hosts to be accessed without needing to pass in the key.

If you're using an account manager you can set it by passing the url with the `-acct_mgr` option. This also requires the '-user' and '-pass' options to supply the username and password for the account manager. Once the account manager is set these options do not need to be passed in again, and the username and password are never stored on disk.

Hosts that are accessed via SSH must be configured in the ~/.ssh/config file with an ssh key.

If run without any arguments the program will try to connect to a boinc process at "tcp:localhost". If it can't connect it will offer to start a new boinc process in "~/.boinc" and store the key for it.

