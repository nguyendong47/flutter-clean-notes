#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.expand_path('Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

puts "Configuring CleanNotesWidgetExtension in #{project_path}..."

target_name = 'CleanNotesWidgetExtension'
bundle_id = 'com.example.flutterCleanNotes.CleanNotesWidgetExtension'
app_group_id = 'group.com.cleannotes.app'

# 1. Find or create extension target
extension_target = project.targets.find { |t| t.name == target_name }
if extension_target
  puts "Target #{target_name} already exists."
else
  extension_target = project.new_target(:app_extension, target_name, :ios, '15.0')
  puts "Created target #{target_name}."
end

# 2. Configure build settings for CleanNotesWidgetExtension
extension_target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['SWIFT_VERSION'] = '5.0'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['SKIP_INSTALL'] = 'YES'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['CODE_SIGN_ENTITLEMENTS'] = 'CleanNotesWidgetExtension/CleanNotesWidgetExtension.entitlements'
  s['INFOPLIST_FILE'] = 'CleanNotesWidgetExtension/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['MARKETING_VERSION'] = '1.0'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = ''
  s['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
  if config.name == 'Debug'
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    s['MTL_ENABLE_DEBUG_INFO'] = 'INCLUDE_SOURCE'
  else
    s['SWIFT_OPTIMIZATION_LEVEL'] = '-Owholemodule'
    s['VALIDATE_PRODUCT'] = 'YES'
  end
end
puts "Configured build settings for #{target_name}."

# 3. Configure build settings for Runner (App Group entitlements)
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found" unless runner_target

runner_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
puts "Set CODE_SIGN_ENTITLEMENTS for Runner."

# 4. File references & Groups
# In Runner group, add Runner.entitlements
runner_group = project.main_group.children.find { |c| c.display_name == 'Runner' }
if runner_group
  unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
    runner_group.new_file('Runner.entitlements')
    puts "Added Runner.entitlements to Runner group."
  end
end

# In Main group, create/find CleanNotesWidgetExtension group
ext_group = project.main_group.children.find { |c| c.display_name == target_name }
unless ext_group
  ext_group = project.main_group.new_group(target_name, target_name)
  puts "Created group #{target_name}."
end

files_to_add = [
  'CleanNotesWidgetBundle.swift',
  'QuickActionsWidget.swift',
  'PinnedNoteWidget.swift',
  'AuroraWidgetTheme.swift',
  'Info.plist',
  'CleanNotesWidgetExtension.entitlements'
]

swift_sources = [
  'CleanNotesWidgetBundle.swift',
  'QuickActionsWidget.swift',
  'PinnedNoteWidget.swift',
  'AuroraWidgetTheme.swift'
]

files_to_add.each do |filename|
  file_ref = ext_group.files.find { |f| f.path == filename }
  unless file_ref
    file_ref = ext_group.new_file(filename)
    puts "Added file reference #{filename} to #{target_name} group."
  end

  if swift_sources.include?(filename)
    sources_phase = extension_target.source_build_phase
    unless sources_phase.files_references.include?(file_ref)
      sources_phase.add_file_reference(file_ref)
      puts "Added #{filename} to Sources build phase of #{target_name}."
    end
  end
end

# 5. Wire Runner dependency on CleanNotesWidgetExtension
unless runner_target.dependencies.any? { |d| d.target == extension_target }
  runner_target.add_dependency(extension_target)
  puts "Added #{target_name} as target dependency of Runner."
end

# 6. Wire Embed Foundation Extensions copy-files phase on Runner
embed_phase = runner_target.copy_files_build_phases.find { |bp| bp.name == 'Embed Foundation Extensions' }
unless embed_phase
  embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
  puts "Created 'Embed Foundation Extensions' copy-files build phase on Runner."
end

embed_phase.dst_subfolder_spec = '13' # PlugIns
embed_phase.dst_path = ''

unless embed_phase.files_references.include?(extension_target.product_reference)
  build_file = embed_phase.add_file_reference(extension_target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "Added #{extension_target.product_reference.display_name} to Embed Foundation Extensions."
end

# Reorder build phases if needed: embed before Thin Binary, after Embed Frameworks
thin_idx = runner_target.build_phases.index { |bp| bp.display_name == 'Thin Binary' }
embed_idx = runner_target.build_phases.index(embed_phase)
if thin_idx && embed_idx && embed_idx > thin_idx
  runner_target.build_phases.delete_at(embed_idx)
  runner_target.build_phases.insert(thin_idx, embed_phase)
  puts "Reordered Embed Foundation Extensions before Thin Binary."
end

# 7. Save project
project.save
puts "Successfully saved #{project_path}."
