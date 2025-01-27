import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart';
import 'package:pathplanner/robot_path/robot_path.dart';
import 'package:pathplanner/services/undo_redo.dart';
import 'package:pathplanner/widgets/custom_appbar.dart';
import 'package:pathplanner/widgets/deploy_fab.dart';
import 'package:pathplanner/widgets/drawer_tiles/path_tile.dart';
import 'package:pathplanner/widgets/drawer_tiles/settings_tile.dart';
import 'package:pathplanner/widgets/keyboard_shortcuts/keyboard_shortcuts.dart';
import 'package:pathplanner/widgets/path_editor/path_editor.dart';
import 'package:pathplanner/widgets/update_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  HomePage() : super();

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String _version = '2022.1.1';
  Directory? _currentProject;
  Directory? _pathsDir;
  late SharedPreferences _prefs;
  List<RobotPath> _paths = [];
  RobotPath? _currentPath;
  double _robotWidth = 0.75;
  double _robotLength = 1.0;
  bool _holonomicMode = false;
  bool _generateJSON = false;
  bool _generateCSV = false;
  late AnimationController _welcomeController;
  late Animation<double> _scaleAnimation;
  SecureBookmarks? _bookmarks = Platform.isMacOS ? SecureBookmarks() : null;
  bool _appStoreBuild = false;

  @override
  void initState() {
    super.initState();
    _welcomeController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 400));
    _scaleAnimation =
        CurvedAnimation(parent: _welcomeController, curve: Curves.ease);
    SharedPreferences.getInstance().then((prefs) async {
      String? projectDir = prefs.getString('currentProjectDir');
      String? pathsDir = prefs.getString('currentPathsDir');
      if (projectDir != null && Platform.isMacOS) {
        if (prefs.getString('macOSBookmark') != null) {
          await _bookmarks!.resolveBookmark(prefs.getString('macOSBookmark')!);

          await _bookmarks!
              .startAccessingSecurityScopedResource(File(projectDir));
        } else {
          projectDir = null;
        }
      }

      setState(() {
        _prefs = prefs;
        _welcomeController.forward();

        _loadPaths(projectDir, pathsDir);
        _robotWidth = _prefs.getDouble('robotWidth') ?? 0.75;
        _robotLength = _prefs.getDouble('robotLength') ?? 1.0;
        _holonomicMode = _prefs.getBool('holonomicMode') ?? false;
        _generateJSON = _prefs.getBool('generateJSON') ?? false;
        _generateCSV = _prefs.getBool('generateCSV') ?? false;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _welcomeController.dispose();
    if (Platform.isMacOS && _currentProject != null) {
      _bookmarks!
          .stopAccessingSecurityScopedResource(File(_currentProject!.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
          _currentPath == null ? 'PathPlanner' : _currentPath!.name),
      drawer: _currentProject == null ? null : _buildDrawer(context),
      body: Stack(
        children: [
          _buildBody(context),
          if (!_appStoreBuild) UpdateCard(_version),
        ],
      ),
      floatingActionButton: Visibility(
        visible:
            _currentProject != null && (!_appStoreBuild && !Platform.isMacOS),
        child: DeployFAB(_currentProject),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            child: Stack(
              children: [
                Container(
                  child: Align(
                      alignment: FractionalOffset.bottomRight,
                      child: Text('v' + _version)),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(),
                        flex: 2,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          (_currentProject != null)
                              ? basename(_currentProject!.path)
                              : 'No Project',
                          style: TextStyle(
                              fontSize: 20,
                              color: (_currentProject != null)
                                  ? Colors.white
                                  : Colors.red),
                        ),
                      ),
                      ElevatedButton(
                          onPressed: () {
                            _openProjectDialog(context);
                          },
                          child: Text('Switch Project')),
                      Expanded(
                        child: Container(),
                        flex: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView(
              padding: EdgeInsets.zero,
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final RobotPath path = _paths.removeAt(oldIndex);
                  _paths.insert(newIndex, path);

                  List<String> pathOrder = [];
                  for (RobotPath path in _paths) {
                    pathOrder.add(path.name);
                  }
                  _prefs.setStringList('pathOrder', pathOrder);
                });
              },
              children: [
                for (int i = 0; i < _paths.length; i++)
                  PathTile(
                    _paths[i],
                    key: Key('$i'),
                    isSelected: _paths[i] == _currentPath,
                    onRename: (name) {
                      File pathFile =
                          File(_pathsDir!.path + _paths[i].name + '.path');
                      File newPathFile = File(_pathsDir!.path + name + '.path');
                      if (newPathFile.existsSync() &&
                          newPathFile.path != pathFile.path) {
                        Navigator.of(context).pop();
                        showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return KeyBoardShortcuts(
                                keysToPress: {LogicalKeyboardKey.enter},
                                onKeysPressed: Navigator.of(context).pop,
                                child: AlertDialog(
                                  title: Text('Unable to Rename'),
                                  content: Text(
                                      'The file "${basename(newPathFile.path)}" already exists'),
                                  actions: [
                                    TextButton(
                                      onPressed: Navigator.of(context).pop,
                                      child: Text(
                                        'OK',
                                        style: TextStyle(
                                            color: Colors.indigoAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            });
                        return false;
                      } else {
                        pathFile.rename(_pathsDir!.path + name + '.path');
                        setState(() {
                          //flutter weird
                          _currentPath!.name = _currentPath!.name;
                        });
                        return true;
                      }
                    },
                    onTap: () {
                      setState(() {
                        _currentPath = _paths[i];
                        UndoRedo.clearHistory();
                      });
                    },
                    onDelete: () {
                      UndoRedo.clearHistory();

                      File pathFile =
                          File(_pathsDir!.path + _paths[i].name + '.path');

                      if (pathFile.existsSync()) {
                        // The fitted text field container does not rebuild
                        // itself correctly so this is a way to hide it and
                        // avoid confusion
                        Navigator.of(context).pop();

                        showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              void confirm() {
                                Navigator.of(context).pop();
                                pathFile.delete();
                                setState(() {
                                  if (_currentPath == _paths.removeAt(i)) {
                                    _currentPath = _paths.first;
                                  }
                                });
                              }

                              return KeyBoardShortcuts(
                                keysToPress: {LogicalKeyboardKey.enter},
                                onKeysPressed: confirm,
                                child: AlertDialog(
                                  title: Text('Delete Path'),
                                  content: Text(
                                      'Are you sure you want to delete "${_paths[i].name}"? This cannot be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                            color: Colors.indigoAccent),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: confirm,
                                      child: Text(
                                        'Confirm',
                                        style: TextStyle(
                                            color: Colors.indigoAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            });
                      } else {
                        setState(() {
                          if (_currentPath == _paths.removeAt(i)) {
                            _currentPath = _paths.first;
                          }
                        });
                      }
                    },
                    onDuplicate: () {
                      UndoRedo.clearHistory();
                      setState(() {
                        List<String> pathNames = [];
                        for (RobotPath path in _paths) {
                          pathNames.add(path.name);
                        }
                        String pathName = _paths[i].name + ' Copy';
                        while (pathNames.contains(pathName)) {
                          pathName = pathName + ' Copy';
                        }
                        _paths.add(RobotPath(
                          RobotPath.cloneWaypointList(_paths[i].waypoints),
                          name: pathName,
                        ));
                        _currentPath = _paths.last;
                        _currentPath!.savePath(
                            _pathsDir!.path, _generateJSON, _generateCSV);
                      });
                    },
                  ),
              ],
            ),
          ),
          Container(
            child: Align(
              alignment: FractionalOffset.bottomCenter,
              child: Container(
                child: Column(
                  children: [
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.add),
                      title: Text('Add Path'),
                      onTap: () {
                        List<String> pathNames = [];
                        for (RobotPath path in _paths) {
                          pathNames.add(path.name);
                        }
                        String pathName = 'New Path';
                        while (pathNames.contains(pathName)) {
                          pathName = 'New ' + pathName;
                        }
                        setState(() {
                          _paths.add(RobotPath.defaultPath(name: pathName));
                          _currentPath = _paths.last;
                          _currentPath!.savePath(
                              _pathsDir!.path, _generateJSON, _generateCSV);
                          UndoRedo.clearHistory();
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: SettingsTile(
                        onSettingsChanged: () {
                          setState(() {
                            _robotWidth =
                                _prefs.getDouble('robotWidth') ?? 0.75;
                            _robotLength =
                                _prefs.getDouble('robotLength') ?? 1.0;
                            _holonomicMode =
                                _prefs.getBool('holonomicMode') ?? false;
                            _generateJSON =
                                _prefs.getBool('generateJSON') ?? false;
                            _generateCSV =
                                _prefs.getBool('generateCSV') ?? false;
                          });
                        },
                        onGenerationEnabled: () {
                          for (RobotPath path in _paths) {
                            path.savePath(
                                _pathsDir!.path, _generateJSON, _generateCSV);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_currentProject != null) {
      return Center(
        child: Container(
          child: PathEditor(_currentPath!, _robotWidth, _robotLength,
              _holonomicMode, _generateJSON, _generateCSV, _pathsDir!.path),
        ),
      );
    } else {
      return Stack(
        children: [
          Center(
              child: Padding(
            padding: const EdgeInsets.all(48.0),
            child: Image.asset('images/field22.png'),
          )),
          Center(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.15),
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                              width: 250,
                              height: 250,
                              child: Image(
                                image: AssetImage('images/icon.png'),
                              )),
                          Text(
                            'PathPlanner',
                            style: TextStyle(fontSize: 48),
                          ),
                          SizedBox(height: 96),
                          ElevatedButton(
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Text(
                                'Open Robot Project',
                                style: TextStyle(fontSize: 24),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                                primary: Colors.grey[700]),
                            onPressed: () {
                              _openProjectDialog(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  void _loadPaths(String? projectDir, String? pathsDir) {
    if (projectDir != null && pathsDir != null) {
      List<RobotPath> paths = [];
      _currentProject = Directory(projectDir);
      _pathsDir = Directory(pathsDir);
      if (!_pathsDir!.existsSync()) {
        _pathsDir!.createSync(recursive: true);
      }
      List<FileSystemEntity> pathFiles = _pathsDir!.listSync();
      for (FileSystemEntity e in pathFiles) {
        if (e.path.endsWith('.path')) {
          String json = File(e.path).readAsStringSync();
          RobotPath p = RobotPath.fromJson(jsonDecode(json));
          p.name = basenameWithoutExtension(e.path);
          paths.add(p);
        }
      }
      List<String>? pathOrder = _prefs.getStringList('pathOrder');
      List<String> loadedOrder = [];
      for (RobotPath path in paths) {
        loadedOrder.add(path.name);
      }
      List<RobotPath> orderedPaths = [];
      if (pathOrder != null) {
        for (String name in pathOrder) {
          int loadedIndex = loadedOrder.indexOf(name);
          if (loadedIndex != -1) {
            loadedOrder.removeAt(loadedIndex);
            orderedPaths.add(paths.removeAt(loadedIndex));
          }
        }
        for (RobotPath path in paths) {
          orderedPaths.add(path);
        }
      } else {
        orderedPaths = paths;
      }
      if (orderedPaths.length == 0) {
        orderedPaths.add(RobotPath.defaultPath());
      }
      _paths = orderedPaths;
      _currentPath = _paths[0];
    }
  }

  void _openProjectDialog(BuildContext context) async {
    var projectFolder = await getDirectoryPath(
        confirmButtonText: 'Open Project',
        initialDirectory: Directory.current.path);
    if (projectFolder != null) {
      File buildFile = File(projectFolder + '/build.gradle');

      Directory pathsDir;
      if (buildFile.existsSync()) {
        // Java or C++ project
        pathsDir = Directory(projectFolder + '/src/main/deploy/pathplanner/');
      } else {
        // Other language
        pathsDir = Directory(projectFolder + '/deploy/pathplanner/');
      }

      pathsDir.createSync(recursive: true);
      _prefs.setString('currentProjectDir', projectFolder);
      _prefs.setString('currentPathsDir', pathsDir.path);
      _prefs.remove('pathOrder');

      if (Platform.isMacOS) {
        // Bookmark project on macos so it can be accessed again later
        String bookmark = await _bookmarks!.bookmark(File(projectFolder));
        _prefs.setString('macOSBookmark', bookmark);
      }

      setState(() {
        _currentProject = Directory(projectFolder);
        _loadPaths(_currentProject!.path, pathsDir.path);
      });
    }
  }
}
