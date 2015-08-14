Pod::Spec.new do |s|

# Root specification

s.name                  = "mishmesh"
s.version               = "1.0.1"
s.summary               = "Mishmesh library"
s.homepage              = "https://github.com/vovagalchenko/mishmesh"
s.license               = { :type => "MIT", :file => "LICENSE" }
s.author                = "Vova Galchenko"
s.source                = { :git => "https://github.com/vovagalchenko/mishmesh.git", :tag => "v#{s.version}" }

# Platform

s.ios.deployment_target = "7.0"

# File patterns

s.ios.source_files        = "MishMesh/MishMesh/*.{h,m}"
s.ios.public_header_files = "MishMesh/MishMesh/*.{h}"


# Build settings
s.ios.frameworks        = "CoreGraphics", "CoreMotion"
s.requires_arc          = true
s.ios.header_dir        = "mishmesh"
s.xcconfig              = { "OTHER_LDFLAGS" => "-ObjC -all_load" }

end

