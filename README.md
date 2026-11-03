### Use

1. Close GTA V and Rockstar Games Launcher.
2. Run `RCloudTools.bat`.
3. Wait while the tool recursively scans the available filesystem drives.
4. Choose **Clear Rockstar profile data** or **Clear Rockstar Launcher data**.
5. Review the discovered locations and choose the move option from the menu.

The scan reads every discovered profile directory recursively and reports its file count and total size. Locations are saved in `RCloudTools.config` beside the batch file.

The selected data is copied into a timestamped folder under `Backups`, verified, and then moved out of the original location. Use **Delete backups permanently** only when you are certain the backup is no longer needed. This is the only action that permanently deletes data.

The scan finds directories named `Profiles` below rockstar Games paths, classifying paths containing `Launcher` as launcher data and other Rockstar profile paths as rockstar profile data. full drive scans can take time and inaccessible directories are skipped. Close GTA V and rockstar Games Launcher before moving data.

