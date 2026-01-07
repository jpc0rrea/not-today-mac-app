# NotToday Podfile
# Run 'pod install' after creating this file

platform :osx, '13.0'
use_frameworks!

target 'NotToday' do
  # Paddle SDK for licensing and payments
  # Note: You may need to add the Paddle framework manually if not available via CocoaPods
  # Download from: https://github.com/PaddleHQ/Mac-Framework-V4/releases
  # pod 'PaddleV4'

  # Alternative: Use SPM or manual framework integration
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
