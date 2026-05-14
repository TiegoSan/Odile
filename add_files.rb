require 'xcodeproj'
project_path = 'Odile.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

features_group = project.main_group.groups.find { |g| g.name == 'Features' } || project.main_group.new_group('Features')

# Add Intent
app_intents_group = features_group.groups.find { |g| g.name == 'AppIntents' } || features_group.new_group('AppIntents', 'Features/AppIntents')
intent_file = app_intents_group.new_file('AnalyzeAudioIntent.swift')
target.source_build_phase.add_file_reference(intent_file)

# Add Folder Watcher
watcher_group = features_group.groups.find { |g| g.name == 'FolderWatcher' } || features_group.new_group('FolderWatcher', 'Features/FolderWatcher')
watcher_file = watcher_group.new_file('FolderWatcherService.swift')
target.source_build_phase.add_file_reference(watcher_file)

project.save
