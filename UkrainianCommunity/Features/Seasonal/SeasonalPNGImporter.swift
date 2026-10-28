import Foundation
import ImageIO
import UIKit

enum SeasonalPNGImporter {
    static func frame(_ data:Data) throws -> String {
        guard data.count<=5_000_000,data.starts(with:[137,80,78,71,13,10,26,10]),
              let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetCount(source)==1,
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int,let height=properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width),(1...4096).contains(height),width*height<=8_388_608 else { throw SeasonalError.invalidPackage }
        for side in [256,192,160,128,96] {
            let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:side,kCGImageSourceCreateThumbnailWithTransform:true]
            if let cg=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary),let png=UIImage(cgImage:cg).pngData(),png.count<=48_000 {
                return png.base64EncodedString()
            }
        }
        throw SeasonalError.invalidPackage
    }
}
