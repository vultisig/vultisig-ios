require 'xcodeproj'

project_path = 'VultisigApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'VultisigApp' }

# Files to clean up
files_to_clean = [
  'PendingTransaction.swift',
  'TransactionStatus.swift',
  'TransactionStatusProvider.swift',
  'TransactionStatusService.swift',
  'PendingTransactionStorage.swift',
  'BackgroundTransactionPoller.swift',
  'EVMTransactionStatusProvider.swift',
  'UTXOTransactionStatusProvider.swift',
  'CosmosTransactionStatusProvider.swift',
  'SolanaTransactionStatusProvider.swift',
  'TransactionStatusViewModel.swift',
  'UTXOTransactionStatusAPI.swift',
  'CosmosTransactionStatusAPI.swift',
  'SolanaTransactionStatusAPI.swift',
  'UTXOTransactionStatusResponse.swift',
  'CosmosTransactionStatusResponse.swift',
  'SolanaTransactionStatusResponse.swift'
]

puts "🧹 Removing all references to transaction status files..."

# Remove from build phase (all instances)
build_files_to_remove = []
app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  next unless build_file.file_ref.path
  if files_to_clean.include?(build_file.file_ref.path)
    build_files_to_remove << build_file
  end
end

build_files_to_remove.each do |build_file|
  if build_file.file_ref && build_file.file_ref.path
    file_path = build_file.file_ref.path
    app_target.source_build_phase.remove_file_reference(build_file.file_ref)
    puts "  Removed from build phase: #{file_path}"
  end
end

# Function to recursively remove files from groups
def remove_files_from_group(group, filenames, removed_count = {})
  return removed_count unless group

  children_to_remove = []

  group.children.each do |child|
    next unless child

    if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
      if child.path && filenames.include?(child.path)
        puts "  Removing file reference: #{child.path} from group: #{group.name || 'root'}"
        removed_count[child.path] = (removed_count[child.path] || 0) + 1
        children_to_remove << child
      end
    elsif child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      remove_files_from_group(child, filenames, removed_count)
    end
  end

  # Remove after iteration to avoid modifying collection while iterating
  children_to_remove.each do |child|
    group.remove_reference(child)
  end

  removed_count
end

# Remove all file references from entire project
removed_count = remove_files_from_group(project.main_group, files_to_clean)

puts "\n📊 Removal summary:"
removed_count.each do |filename, count|
  puts "  #{filename}: #{count} reference(s) removed"
end

# Remove TransactionStatus group if it exists
services_group = project.main_group['VultisigApp']&.[]('Services')
if services_group && services_group['TransactionStatus']
  puts "\n  Removing TransactionStatus group..."
  services_group.remove_reference(services_group['TransactionStatus'])
end

puts "\n✅ Successfully removed all duplicate references"
project.save
puts "💾 Project saved"
