require 'xcodeproj'
project_path = '/Users/gautier/GogoLabs/Odile/Odile.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
file_ref = project.main_group.new_file('App/OdileViewModel.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
