//
//  ITVTiledView.swift
//  Pods
//
//  Created by Jakub Fiser on 13/10/2016.
//
//

import UIKit

class ITVTiledView: UIView {

    internal var image: ITVImageDescriptor! {
        didSet {
            backgroundView?.image = image
            
            let l = layer as! CATiledLayer
            if let size = try? image.tileSize[level] {
                l.tileSize = size
            }
            l.levelsOfDetail = image.zoomScales.count
            
            // must be on main thread
            self.setNeedsLayout()
        }
    }
    
    internal var backgroundView: ITVBackgroundView?
    
    internal var itvDelegate: ITVScrollViewDelegate?
    fileprivate var imageCache = [String:UIImage]()
    fileprivate var lastLevel: Int = -1
    fileprivate var level: Int {
        get {
            return Int(round(log2(contentScaleFactor)))
        }
    }
    override var contentScaleFactor: CGFloat {
        didSet {
            // pass cache with new images to background tiled view
            backgroundView?.addToCache(dict: imageCache)
            backgroundView?.setScaleFor(level: level)
            
            // reset cache of CATiledLayer
            refreshLayout()
        }
    }
    
    /// use specific subclass of CALayer, that allows tile based image rendering
    override class var layerClass: AnyClass {
        return CATiledLayer.self
    }
    
    init() {
        super.init(frame: CGRect.zero)
        
        // provide transparent background for easy customization in storyboard
        backgroundColor = UIColor.clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func clearCache() {
        imageCache.removeAll()
    }
    
    func refreshLayout() {
        layer.contents = nil
        layer.setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        
        guard image != nil, let context = UIGraphicsGetCurrentContext(), !rect.isInfinite, !rect.isNull else {
            return
        }
        
        let viewScale = self.contentScaleFactor
        let viewSize = bounds.width * contentScaleFactor
        
        let scale = CGFloat(image.width)/viewSize
        
        let tiledLayer = self.layer as! CATiledLayer
        let tileSize = tiledLayer.tileSize
        
        let column = Int(rect.midX * viewScale / tileSize.width)
        let row = Int(rect.midY * viewScale / tileSize.height)
        let level = self.level
        
        /// TODO: make borders setting modifiable to user as well
        let displayTileBorders = false
        
        let cacheKey = "\(level)-\(column)-\(row)"
        if let image = imageCache[cacheKey] {
            image.draw(in: rect)
        }
        else if let requestURL = image.getUrl(x: column, y: row, level: level, scale: scale) {
            URLSession.shared.dataTask(with: requestURL, completionHandler: { (data, response, error) in
                if data != nil {
                    if let img = UIImage(data: data!) {
                        self.imageCache[cacheKey] = img
                        DispatchQueue.main.async {
                            self.setNeedsDisplay(rect)
                        }
                    } else {
                        let msg = "Error decoding image from \(requestURL.absoluteString)."
                        let error = NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY: msg])
                        self.itvDelegate?.errorDidOccur(error: error)
                    }
                } else {
                    let errorCode = (response as! HTTPURLResponse).statusCode
                    let msg = "Error \(errorCode) downloading image from \(requestURL.absoluteString)."
                    let error = NSError(domain: Constants.TAG, code: errorCode, userInfo: [Constants.USERINFO_KEY: msg])
                    self.itvDelegate?.errorDidOccur(error: error)
                }
            }).resume()
        } else {
            // probably out of image's bounds
            print("Request for non-existing tile at \(level):[\(column),\(row)].")
        }
        
        if displayTileBorders {
            UIColor.green.set()
            context.setLineWidth(1)
            context.stroke(rect)
        }
    }
}
