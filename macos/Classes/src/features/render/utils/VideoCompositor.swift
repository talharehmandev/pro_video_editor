import AVFoundation
import AppKit
import CoreImage

class VideoCompositor: NSObject, AVVideoCompositing {
    var blurSigma: Double = 0.0
    var overlayImage: CIImage?
    var imageBytesWithCropping: Bool = false

    var rotateRadians: Double = 0
    var rotateTurns: Int = 0
    var flipX: Bool = false
    var flipY: Bool = false
    var cropX: CGFloat = 0
    var cropY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var cropWidth: CGFloat?
    var cropHeight: CGFloat?

    var originalNaturalSize: CGSize = .zero

    private let lutQueue = DispatchQueue(label: "lut.queue")
    private var _lutData: Data?
    private var _lutSize: Int = 33

    static var config = VideoCompositorConfig()

    required override init() {
        super.init()
        apply(Self.config)
    }

    var videoRotationDegrees: Double = 0.0
    var shouldApplyOrientationCorrection: Bool = false

    func apply(_ config: VideoCompositorConfig) {
        self.blurSigma = config.blurSigma
        self.rotateRadians = config.rotateRadians
        self.rotateTurns = config.rotateTurns
        self.flipX = config.flipX
        self.flipY = config.flipY
        self.cropX = config.cropX
        self.cropY = config.cropY
        self.cropWidth = config.cropWidth
        self.cropHeight = config.cropHeight
        self.scaleX = config.scaleX
        self.scaleY = config.scaleY
        self.imageBytesWithCropping = config.imageBytesWithCropping

        // Apply rotation metadata properties
        self.videoRotationDegrees = config.videoRotationDegrees
        self.shouldApplyOrientationCorrection = config.shouldApplyOrientationCorrection
        self.originalNaturalSize = config.originalNaturalSize

        self.setOverlayImage(from: config.overlayImage)
        self.setLUT(data: config.lutData, size: config.lutSize)
    }

    func setOverlayImage(from data: Data?) {
        guard let data,
            let nsImage = NSImage(data: data),
            let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            overlayImage = nil
            return
        }

        overlayImage = CIImage(cgImage: cgImage)
    }

    func clearLUT() {
        lutQueue.sync {
            _lutData = nil
        }
    }
    func setLUT(data: Data?, size: Int) {
        lutQueue.sync {
            _lutData = data
            _lutSize = size
        }
    }

    private func getLUT() -> (data: Data?, size: Int) {
        lutQueue.sync {
            (_lutData, _lutSize)
        }
    }

    private static let sharedContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .useSoftwareRenderer: false,
    ])

    var sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let renderSize = request.renderContext.size
        
        guard
            let sourceBuffer = request.sourceFrame(byTrackID: request.sourceTrackIDs[0].int32Value)
        else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 0))
            return
        }

        // Fast path for identity frames when no custom effects are present
        // (Though RenderVideo level bypass already handles most of this)
        let isSimpleFrame = blurSigma <= 0 && 
                            getLUT().data == nil && 
                            overlayImage == nil && 
                            rotateRadians == 0 && 
                            flipX == false && 
                            flipY == false && 
                            scaleX == 1 && 
                            scaleY == 1 && 
                            cropWidth == nil && 
                            cropHeight == nil
        
        if isSimpleFrame {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        var outputImage = CIImage(cvPixelBuffer: sourceBuffer)
        let inputExtent = outputImage.extent
        
        // Apply layer instruction transform first (video scaling/centering/rotation)
        if let instruction = request.videoCompositionInstruction as? AVMutableVideoCompositionInstruction,
           let layerInstruction = instruction.layerInstructions.first as? AVMutableVideoCompositionLayerInstruction {
            
            var startTransform = CGAffineTransform.identity
            var endTransform = CGAffineTransform.identity
            var timeRange = CMTimeRange.zero
            
            let hasTransform = layerInstruction.getTransformRamp(
                for: request.compositionTime,
                start: &startTransform,
                end: &endTransform,
                timeRange: &timeRange
            )
            
            if hasTransform && !startTransform.isIdentity {
                let imageHeight = outputImage.extent.height
                let flipY = CGAffineTransform(scaleX: 1, y: -1)
                    .translatedBy(x: 0, y: -imageHeight)
                
                let convertedTransform = flipY.concatenating(startTransform)
                outputImage = outputImage.transformed(by: convertedTransform)
                
                let transformedExtent = outputImage.extent
                let newHeight = transformedExtent.height
                let flipBack = CGAffineTransform(scaleX: 1, y: -1)
                    .translatedBy(x: 0, y: -newHeight)
                
                outputImage = outputImage.transformed(by: flipBack)
                
                let finalExtent = outputImage.extent
                if finalExtent.origin.x != 0 || finalExtent.origin.y != 0 {
                    let translation = CGAffineTransform(
                        translationX: -finalExtent.origin.x,
                        y: -finalExtent.origin.y
                    )
                    outputImage = outputImage.transformed(by: translation)
                }
            }
        }

        var center = CGPoint(x: outputImage.extent.midX, y: outputImage.extent.midY)

        // Apply LUT, blur, and flip BEFORE overlay when imageBytesWithCropping is enabled
        if imageBytesWithCropping {
            let (lutData, lutSize) = getLUT()
            if let lutData,
                let lutFilter = CIFilter(name: "CIColorCube")
            {
                lutFilter.setValue(lutSize, forKey: "inputCubeDimension")
                lutFilter.setValue(lutData, forKey: "inputCubeData")
                lutFilter.setValue(outputImage, forKey: kCIInputImageKey)
                if let filteredImage = lutFilter.outputImage {
                    outputImage = filteredImage
                }
            }
            
            if blurSigma > 0 {
                // Blur expands the image extent. We MUST crop it to keep it efficient.
                let preBlurExtent = outputImage.extent
                outputImage = outputImage.applyingGaussianBlur(sigma: blurSigma)
                    .cropped(to: preBlurExtent)
            }
            
            if flipX || flipY {
                let flipTransform = CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
                    .translatedBy(x: -center.x, y: -center.y)

                outputImage = outputImage.transformed(by: flipTransform)
                let flippedExtent = outputImage.extent
                if flippedExtent.origin.x != 0 || flippedExtent.origin.y != 0 {
                    outputImage = outputImage.transformed(by: CGAffineTransform(translationX: -flippedExtent.origin.x, y: -flippedExtent.origin.y))
                }
                center = CGPoint(x: outputImage.extent.midX, y: outputImage.extent.midY)
            }
        }
        
        if imageBytesWithCropping, let overlay = overlayImage {
            let imageRect = outputImage.extent
            let scaledOverlay = overlay.transformed(
                by: CGAffineTransform(
                    scaleX: imageRect.width / overlay.extent.width,
                    y: imageRect.height / overlay.extent.height))
            outputImage = scaledOverlay.composited(over: outputImage)
        }

        // Cropping
        if cropX != 0 || cropY != 0 || cropWidth != nil || cropHeight != nil {
            let videoWidth = outputImage.extent.width
            let videoHeight = outputImage.extent.height

            let width = cropWidth ?? (videoWidth - cropX)
            let height = cropHeight ?? (videoHeight - cropY)
            let y = videoHeight - height - cropY

            let cropRect = CGRect(x: cropX, y: y, width: width, height: height)
            outputImage = outputImage.cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
            center = CGPoint(x: outputImage.extent.midX, y: outputImage.extent.midY)
        }

        // Rotation
        if rotateRadians != 0 {
            let rotatedImage = outputImage.transformed(by: CGAffineTransform(rotationAngle: rotateRadians))
            let rotatedExtent = rotatedImage.extent
            outputImage = rotatedImage.transformed(by: CGAffineTransform(translationX: -rotatedExtent.origin.x, y: -rotatedExtent.origin.y))
            center = CGPoint(x: outputImage.extent.midX, y: outputImage.extent.midY)
        }

        // Final Transform (Flipping and Scaling)
        var finalTransform = CGAffineTransform.identity
        if !imageBytesWithCropping && (flipX || flipY) {
            finalTransform = finalTransform
                .translatedBy(x: center.x, y: center.y)
                .scaledBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
                .translatedBy(x: -center.x, y: -center.y)
        }

        if scaleX != 1 || scaleY != 1 {
            finalTransform = finalTransform.scaledBy(x: scaleX, y: scaleY)
        }

        if finalTransform != .identity {
            outputImage = outputImage.transformed(by: finalTransform)
        }

        // Apply LUT and Blur (Standard path)
        if !imageBytesWithCropping {
            let (lutData, lutSize) = getLUT()
            if let lutData,
                let lutFilter = CIFilter(name: "CIColorCube")
            {
                lutFilter.setValue(lutSize, forKey: "inputCubeDimension")
                lutFilter.setValue(lutData, forKey: "inputCubeData")
                lutFilter.setValue(outputImage, forKey: kCIInputImageKey)
                if let filteredImage = lutFilter.outputImage {
                    outputImage = filteredImage
                }
            }

            if blurSigma > 0 {
                let preBlurExtent = outputImage.extent
                outputImage = outputImage.applyingGaussianBlur(sigma: blurSigma)
                    .cropped(to: preBlurExtent)
            }
        }

        // Apply overlay image
        if !imageBytesWithCropping, let overlay = overlayImage {
            let imageRect = outputImage.extent
            let scaledOverlay = overlay.transformed(
                by: CGAffineTransform(
                    scaleX: imageRect.width / overlay.extent.width,
                    y: imageRect.height / overlay.extent.height))
            outputImage = scaledOverlay.composited(over: outputImage)
        }

        // Final safety crop to renderSize
        outputImage = outputImage.cropped(to: CGRect(origin: .zero, size: renderSize))

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "VideoCompositor", code: -2, userInfo: nil))
            return
        }

        Self.sharedContext.render(outputImage, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}
