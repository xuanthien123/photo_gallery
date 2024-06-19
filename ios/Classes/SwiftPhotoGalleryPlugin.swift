import Foundation
import MobileCoreServices
import Flutter
import UIKit
import Photos

public class SwiftPhotoGalleryPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "photo_gallery", binaryMessenger: registrar.messenger())
    let instance = SwiftPhotoGalleryPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if(call.method == "listAlbums") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let mediumType = arguments["mediumType"] as? String
      let hideIfEmpty = arguments["hideIfEmpty"] as? Bool
      result(listAlbums(mediumType: mediumType, hideIfEmpty: hideIfEmpty))
    }
    else if(call.method == "listMedia") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let albumId = arguments["albumId"] as! String
      let mediumType = arguments["mediumType"] as? String
      let newest = arguments["newest"] as! Bool
      let skip = arguments["skip"] as? NSNumber
      let take = arguments["take"] as? NSNumber
      let lightWeight = arguments["lightWeight"] as? Bool
      result(listMedia(
        albumId: albumId,
        mediumType: mediumType,
        newest: newest,
        skip: skip,
        take: take,
        lightWeight: lightWeight
      ))
    }
    else if(call.method == "getMedium") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let mediumId = arguments["mediumId"] as! String
      do {
        let medium = try getMedium(mediumId: mediumId)
        result(medium)
      } catch {
        result(nil)
      }
    }
    else if(call.method == "getThumbnail") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let mediumId = arguments["mediumId"] as! String
      let width = arguments["width"] as? NSNumber
      let height = arguments["height"] as? NSNumber
      let highQuality = arguments["highQuality"] as? Bool
      getThumbnail(
        mediumId: mediumId,
        width: width,
        height: height,
        highQuality: highQuality,
        completion: { (data: Data?, error: Error?) -> Void in
          result(data)
        }
      )
    }
    else if(call.method == "getAlbumThumbnail") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let albumId = arguments["albumId"] as! String
      let mediumType = arguments["mediumType"] as? String
      let newest = arguments["newest"] as! Bool
      let width = arguments["width"] as? Int
      let height = arguments["height"] as? Int
      let highQuality = arguments["highQuality"] as? Bool
      getAlbumThumbnail(
        albumId: albumId,
        mediumType: mediumType,
        newest: newest,
        width: width,
        height: height,
        highQuality: highQuality,
        completion: { (data: Data?, error: Error?) -> Void in
          result(data)
        }
      )
    }
    else if(call.method == "getFile") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let mediumId = arguments["mediumId"] as! String
      let mimeType = arguments["mimeType"] as? String
      getFile(
        mediumId: mediumId,
        mimeType: mimeType,
        completion: { (filepath: String?, error: Error?) -> Void in
          result(filepath?.replacingOccurrences(of: "file://", with: ""))
        }
      )
    }
    else if(call.method == "deleteMedium") {
      let arguments = call.arguments as! Dictionary<String, AnyObject>
      let mediumId = arguments["mediumId"] as! String
      deleteMedium(
        mediumId: mediumId,
        completion: { (success: Bool, error: Error?) -> Void in
          result(success)
        }
      )
    }
    else if(call.method == "cleanCache") {
      cleanCache()
      result(nil)
    }
    else {
      result(FlutterMethodNotImplemented)
    }
  }

  private var assetCollections: [PHAssetCollection] = []

  private func listAlbums(mediumType: String?, hideIfEmpty: Bool? = true) -> [[String: Any?]] {
    self.assetCollections = []
    let fetchOptions = PHFetchOptions()
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }
    var albums = [[String: Any?]]()
    var albumIds = Set<String>()

    func addCollection (collection: PHAssetCollection, hideIfEmpty: Bool) -> Void {
      let kRecentlyDeletedCollectionSubtype = PHAssetCollectionSubtype(rawValue: 1000000201)
      guard collection.assetCollectionSubtype != kRecentlyDeletedCollectionSubtype else { return }

      // De-duplicate by id.
      let albumId = collection.localIdentifier
      guard !albumIds.contains(albumId) else { return }
      albumIds.insert(albumId)

      let count = countMedia(collection: collection, mediumType: mediumType)
      if(count > 0 || !hideIfEmpty) {
        self.assetCollections.append(collection)
        albums.append([
          "id": collection.localIdentifier,
          "name": collection.localizedTitle ?? "Unknown",
          "count": count,
        ])
      }
    }

    func processPHAssetCollections(fetchResult: PHFetchResult<PHAssetCollection>, hideIfEmpty: Bool) -> Void {
      fetchResult.enumerateObjects { (assetCollection, _, _) in
        addCollection(collection: assetCollection, hideIfEmpty: hideIfEmpty)
      }
    }

    func processPHCollections (fetchResult: PHFetchResult<PHCollection>, hideIfEmpty: Bool) -> Void {
      fetchResult.enumerateObjects { (collection, _, _) in
        if let assetCollection = collection as? PHAssetCollection {
          addCollection(collection: assetCollection, hideIfEmpty: hideIfEmpty)
        } else if let collectionList = collection as? PHCollectionList {
          processPHCollections(
            fetchResult: PHCollectionList.fetchCollections(in: collectionList, options: nil),
            hideIfEmpty: hideIfEmpty
          )
        }
      }
    }

    // Smart Albums.
    processPHAssetCollections(
      fetchResult: PHAssetCollection.fetchAssetCollections(
        with: .smartAlbum,
        subtype: .albumRegular,
        options: fetchOptions
      ),
      hideIfEmpty: hideIfEmpty ?? true
    )

    // User-created collections.
    processPHCollections(
      fetchResult: PHAssetCollection.fetchTopLevelUserCollections(with: fetchOptions),
      hideIfEmpty: hideIfEmpty ?? true
    )

    albums.insert([
      "id": "__ALL__",
      "name": "All",
      "count": countMedia(collection: nil, mediumType: mediumType),
    ], at: 0)

    return albums
  }

  private func countMedia(collection: PHAssetCollection?, mediumType: String?) -> Int {
    let options = PHFetchOptions()
    options.predicate = self.predicateFromMediumType(mediumType: mediumType)
    if(collection == nil) {
      return PHAsset.fetchAssets(with: options).count
    }

    return PHAsset.fetchAssets(in: collection ?? PHAssetCollection.init(), options: options).count
  }

  private func listMedia(
    albumId: String,
    mediumType: String?,
    newest: Bool,
    skip: NSNumber?,
    take: NSNumber?,
    lightWeight: Bool? = false
  ) -> NSDictionary {
    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = predicateFromMediumType(mediumType: mediumType)
    fetchOptions.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: newest ? false : true),
      NSSortDescriptor(key: "modificationDate", ascending: newest ? false : true)
    ]

    let collection = self.assetCollections.first(where: { (collection) -> Bool in
      collection.localIdentifier == albumId
    })

    let fetchResult: PHFetchResult<PHAsset>
    if(albumId == "__ALL__") {
      fetchResult = PHAsset.fetchAssets(with: fetchOptions)
    } else {
      fetchResult = PHAsset.fetchAssets(
        in: collection ?? PHAssetCollection.init(),
        options: fetchOptions
      )
    }
    let start = skip?.intValue ?? 0
    let total = fetchResult.count
    let end = take == nil ? total : min(start + take!.intValue, total)
    var items = [[String: Any?]]()
    for index in start..<end {
      let asset = fetchResult.object(at: index) as PHAsset
      if(lightWeight == true) {
        items.append(getMediumFromAssetLightWeight(asset: asset))
      } else {
        items.append(getMediumFromAsset(asset: asset))
      }
    }

    return [
      "start": start,
      "items": items,
    ]
  }

  private func getMedium(mediumId: String) throws -> [String: Any?] {
    let fetchOptions = PHFetchOptions()
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }
    let assets: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [mediumId], options: fetchOptions)

    if (assets.count <= 0) {
      throw NSError(domain: "photo_gallery", code: 404)
    } else {
      let asset: PHAsset = assets[0]
      return getMediumFromAsset(asset: asset)
    }
  }

  private func getThumbnail(
    mediumId: String,
    width: NSNumber?,
    height: NSNumber?,
    highQuality: Bool?,
    completion: @escaping (Data?, Error?) -> Void
  ) {
    let manager = PHImageManager.default()
    let fetchOptions = PHFetchOptions()
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }
    let assets: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [mediumId], options: fetchOptions)

    if (assets.count > 0) {
      let asset: PHAsset = assets[0]

      let options = PHImageRequestOptions()
      options.isSynchronous = false
      options.version = .current
      options.deliveryMode = (highQuality ?? false) ? .highQualityFormat : .fastFormat
      options.isNetworkAccessAllowed = true

      let imageSize = CGSize(width: width?.intValue ?? 128, height: height?.intValue ?? 128)
      manager.requestImage(
        for: asset,
        targetSize: CGSize(
          width: imageSize.width * UIScreen.main.scale,
          height: imageSize.height * UIScreen.main.scale
        ),
        contentMode: PHImageContentMode.aspectFill,
        options: options,
        resultHandler: { (uiImage: UIImage?, info) in
          guard let image = uiImage else {
            completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
            return
          }
          let bytes = image.jpegData(compressionQuality: CGFloat(70))
          completion(bytes, nil)
        }
      )
      return
    }

    completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
  }

  private func getAlbumThumbnail(
    albumId: String,
    mediumType: String?,
    newest: Bool,
    width: Int?,
    height: Int?,
    highQuality: Bool?,
    completion: @escaping (Data?, Error?) -> Void
  ) {
    let manager = PHImageManager.default()
    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = self.predicateFromMediumType(mediumType: mediumType)
    fetchOptions.sortDescriptors = [
      NSSortDescriptor(key: "creationDate", ascending: !newest),
      NSSortDescriptor(key: "modificationDate", ascending: !newest)
    ]
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }

    let assets: PHFetchResult<PHAsset>
    if(albumId == "__ALL__") {
      assets = PHAsset.fetchAssets(with: fetchOptions)
    } else {
      assets = PHAsset.fetchAssets(in: self.assetCollections.first(where: { (collection) -> Bool in
        collection.localIdentifier == albumId
      })!, options: fetchOptions)
    }

    if (assets.count > 0) {
      let asset: PHAsset = assets[0]

      let options = PHImageRequestOptions()
      options.isSynchronous = false
      options.version = .current
      options.deliveryMode = (highQuality ?? false) ? .highQualityFormat : .fastFormat
      options.isNetworkAccessAllowed = true

      let imageSize = CGSize(width: width ?? 128, height: height ?? 128)
      manager.requestImage(
        for: asset,
        targetSize: CGSize(
          width: imageSize.width * UIScreen.main.scale,
          height: imageSize.height * UIScreen.main.scale
        ),
        contentMode: PHImageContentMode.aspectFill,
        options: options,
        resultHandler: { (uiImage: UIImage?, info) in
          guard let image = uiImage else {
            completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
            return
          }
          let bytes = image.jpegData(compressionQuality: CGFloat(80))
          completion(bytes, nil)
        }
      )
      return
    }

    completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
  }

  private func getFile(mediumId: String, mimeType: String?, completion: @escaping (String?, Error?) -> Void) {
    let manager = PHImageManager.default()

    let fetchOptions = PHFetchOptions()
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }
    let assets: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [mediumId], options: fetchOptions)

    if (assets.count > 0) {
      let asset: PHAsset = assets[0]
      if(asset.mediaType == PHAssetMediaType.image) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        manager.requestImageData(
          for: asset,
          options: options,
          resultHandler: { (data: Data?, uti: String?, orientation, info) in
            DispatchQueue.main.async(execute: {
              guard let imageData = data else {
                completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
                return
              }
              guard let assetUTI = uti else {
                completion(nil, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
                return
              }
              if mimeType != nil {
                let type = self.extractMimeTypeFromUTI(uti: assetUTI)
                if type != mimeType {
                  let path = self.cacheImage(asset: asset, data: imageData, mimeType: mimeType!)
                  completion(path, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
                  return
                }
              }
              let fileExt = self.extractFileExtensionFromUTI(uti: assetUTI)
              let filepath = self.exportPathForAsset(asset: asset, ext: fileExt)
              try! imageData.write(to: filepath, options: .atomic)
              completion(filepath.absoluteString, nil)
            })
          }
        )
      } else if(asset.mediaType == PHAssetMediaType.video || asset.mediaType == PHAssetMediaType.audio) {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        manager.requestAVAsset(
          forVideo: asset,
          options: options,
          resultHandler: { (avAsset, avAudioMix, info) in
            DispatchQueue.main.async(execute: {
              do {
                let avAsset = avAsset as? AVURLAsset
                let data = try Data(contentsOf: avAsset!.url)
                let fileExt = self.extractFileExtensionFromAsset(asset: asset)
                let filepath = self.exportPathForAsset(asset: asset, ext: fileExt)
                try! data.write(to: filepath, options: .atomic)
                completion(filepath.absoluteString, nil)
              } catch {
                completion(nil, NSError(domain: "photo_gallery", code: 500, userInfo: nil))
              }
            })
          }
        )
      }
    }
  }

  private func cacheImage(asset: PHAsset, data: Data, mimeType: String) -> String? {
    if mimeType == "image/jpeg" {
      let filepath = self.exportPathForAsset(asset: asset, ext: ".jpeg")
      let uiImage = UIImage(data: data)
      try! uiImage?.jpegData(compressionQuality: 100)?.write(to: filepath, options: .atomic)
      return filepath.absoluteString
    } else if mimeType == "image/png" {
      let filepath = self.exportPathForAsset(asset: asset, ext: ".png")
      let uiImage = UIImage(data: data)
      try! uiImage?.pngData()?.write(to: filepath, options: .atomic)
      return filepath.absoluteString
    } else {
      return nil
    }
  }

  private func getMediumFromAsset(asset: PHAsset) -> [String: Any?] {
    let filename = self.extractFilenameFromAsset(asset: asset)
    let mimeType = self.extractMimeTypeFromAsset(asset: asset)
    let resource = self.extractResourceFromAsset(asset: asset)
    let size = self.extractSizeFromResource(resource: resource)
    let orientation = self.toOrientationValue(orientation: asset.value(forKey: "orientation") as? UIImage.Orientation)
    return [
      "id": asset.localIdentifier,
      "filename": filename,
      "title": self.extractTitleFromFilename(filename: filename),
      "mediumType": toDartMediumType(value: asset.mediaType),
      "mimeType": mimeType,
      "height": asset.pixelHeight,
      "width": asset.pixelWidth,
      "size": size,
      "orientation": orientation,
      "duration": NSInteger(asset.duration * 1000),
      "creationDate": (asset.creationDate != nil) ? NSInteger(asset.creationDate!.timeIntervalSince1970 * 1000) : nil,
      "modifiedDate": (asset.modificationDate != nil) ? NSInteger(asset.modificationDate!.timeIntervalSince1970 * 1000) : nil
    ]
  }

  private func getMediumFromAssetLightWeight(asset: PHAsset) -> [String: Any?] {
    return [
      "id": asset.localIdentifier,
      "mediumType": toDartMediumType(value: asset.mediaType),
      "height": asset.pixelHeight,
      "width": asset.pixelWidth,
      "duration": NSInteger(asset.duration * 1000),
      "creationDate": (asset.creationDate != nil) ? NSInteger(asset.creationDate!.timeIntervalSince1970 * 1000) : nil,
      "modifiedDate": (asset.modificationDate != nil) ? NSInteger(asset.modificationDate!.timeIntervalSince1970 * 1000) : nil
    ]
  }

  private func exportPathForAsset(asset: PHAsset, ext: String) -> URL {
    let mediumId = asset.localIdentifier
      .replacingOccurrences(of: "/", with: "__")
      .replacingOccurrences(of: "\\", with: "__")
    let cachePath = self.cachePath()
    return cachePath.appendingPathComponent(mediumId + ext)
  }

  private func toSwiftMediumType(value: String) -> PHAssetMediaType? {
    switch value {
    case "image": return PHAssetMediaType.image
    case "video": return PHAssetMediaType.video
    case "audio": return PHAssetMediaType.audio
    default: return nil
    }
  }

  private func toDartMediumType(value: PHAssetMediaType) -> String? {
    switch value {
    case PHAssetMediaType.image: return "image"
    case PHAssetMediaType.video: return "video"
    case PHAssetMediaType.audio: return "audio"
    default: return nil
    }
  }

  private func toOrientationValue(orientation: UIImage.Orientation?) -> Int {
    guard let orientation = orientation else {
      return 0
    }
    switch orientation {
    case UIImage.Orientation.up:
      return 1
    case UIImage.Orientation.down:
      return 3
    case UIImage.Orientation.left:
      return 6
    case UIImage.Orientation.right:
      return 8
    case UIImage.Orientation.upMirrored:
      return 2
    case UIImage.Orientation.downMirrored:
      return 4
    case UIImage.Orientation.leftMirrored:
      return 5
    case UIImage.Orientation.rightMirrored:
      return 7
    @unknown default:
      return 0
    }
  }

  private func predicateFromMediumType(mediumType: String?) -> NSPredicate? {
    guard let type = mediumType else {
      return nil
    }
    guard let swiftType = toSwiftMediumType(value: type) else {
      return nil
    }
    return NSPredicate(format: "mediaType = %d", swiftType.rawValue)
  }

  private func extractFileExtensionFromUTI(uti: String?) -> String {
    guard let assetUTI = uti else {
      return ""
    }
    guard let ext = UTTypeCopyPreferredTagWithClass(
      assetUTI as CFString,
      kUTTagClassFilenameExtension as CFString
    )?.takeRetainedValue() as String? else {
      return ""
    }
    return "." + ext
  }

  private func extractMimeTypeFromUTI(uti: String?) -> String? {
    guard let assetUTI = uti else {
      return nil
    }
    guard let mimeType = UTTypeCopyPreferredTagWithClass(
      assetUTI as CFString,
      kUTTagClassMIMEType as CFString
    )?.takeRetainedValue() as String? else {
      return nil
    }
    return mimeType
  }

  private func extractFileExtensionFromAsset(asset: PHAsset) -> String {
    let uti = asset.value(forKey: "uniformTypeIdentifier") as? String
    return self.extractFileExtensionFromUTI(uti: uti)
  }

  private func extractMimeTypeFromAsset(asset: PHAsset) -> String? {
    let uti = asset.value(forKey: "uniformTypeIdentifier") as? String
    return self.extractMimeTypeFromUTI(uti: uti)
  }

  private func extractFilenameFromAsset(asset: PHAsset) -> String? {
    return asset.value(forKey: "originalFilename") as? String
  }

  private func extractTitleFromFilename(filename: String?) -> String? {
    if let name = filename {
      return (name as NSString).deletingPathExtension
    }
    return nil
  }

  private func extractResourceFromAsset(asset: PHAsset) -> PHAssetResource? {
    if #available(iOS 9, *) {
      let resourceList = PHAssetResource.assetResources(for: asset)
      if let resource = resourceList.first {
        return resource
      }
    }
    return nil
  }

  private func extractSizeFromResource(resource: PHAssetResource?) -> Int64? {
    if let assetResource = resource {
      return assetResource.value(forKey: "fileSize") as? Int64
    }
    return nil
  }

  private func cachePath() -> URL {
    let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    let cacheFolder = paths[0].appendingPathComponent("photo_gallery")
    try! FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true, attributes: nil)
    return cacheFolder
  }

  private func deleteMedium(mediumId: String, completion: @escaping (Bool, Error?) -> Void) {
    let fetchOptions = PHFetchOptions()
    if #available(iOS 9, *) {
      fetchOptions.fetchLimit = 1
    }
    let assets: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [mediumId], options: fetchOptions)

    if assets.count <= 0 {
      completion(false, NSError(domain: "photo_gallery", code: 404, userInfo: nil))
    } else {
      let asset: PHAsset = assets[0]
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
      }, completionHandler: completion)
    }
  }

  private func cleanCache() {
    try? FileManager.default.removeItem(at: self.cachePath())
  }
}
