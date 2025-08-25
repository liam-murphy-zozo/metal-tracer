//
//  Renderer.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

// TODO LIST:
// - Improve camera math, allow for transformation
// - User Input for camera control
// - Multi Sampling per pixel
// - Iterative path tracing (area lights)
// - Mesh loader
// - Triangle/ Mesh Rendering
// - Pack all objects into one uniform
// - Support multiple material types
// - glass support
// - BVH for mesh
// - Mesh and memory optimizations
// - interactive GUI?
// - transformation matrices for objects (actually transforms camera or ray?)
//

import Metal
import MetalKit
import simd

struct Sphere {
    var position: SIMD3<Float>
    var radius: Float

    init(position: SIMD3<Float>, radius: Float) {
        self.position = position
        self.radius = radius
    }

    func isHit(by ray: Ray) -> Ray { // return the normal if hit, otherwise return 000
        let oc = ray.origin - position
        let a = dot(ray.dir, ray.dir) // We can eliminate this if we assume it is normalised.
        let b = 2.0 * dot(oc, ray.dir)
        let c = dot(oc, oc) - radius * radius
        
        let discriminant = b * b - 4.0 * a * c
        
        if discriminant >= 0.0 {
            var t: Float
            if discriminant == 0 {
                t = -b / (2.0 * a)
            } else {
                let t_0 = (-b - sqrt(discriminant)) / (2.0 * a)
                let t_1 = (-b + sqrt(discriminant)) / (2.0 * a)
                t = t_0 < t_1 ? t_0 : t_1
            }
            // calculate norm
            let hit_pos = ray.origin + t * ray.dir
            let normal = normalize(hit_pos - position) // could speed up by dividing by radius instead of using normalize?
            return Ray(origin: hit_pos, dir: normal)
        }

        return Ray(origin: .zero, dir: .zero)
    }
}

struct Camera {
    var position: SIMD3<Float>
    var orientation: matrix_float4x4
    var distanceToPlane: Float
    var height: Float
    var width: Float

    init(position: SIMD3<Float>, orientation: matrix_float4x4, distanceToPlane: Float, height: Float, width: Float) {
        self.position = position
        self.orientation = orientation
        self.distanceToPlane = distanceToPlane
        self.height = height
        self.width = width
    }
}

struct Ray {
    init(origin: SIMD3<Float>, dir: SIMD3<Float>) {
        self.origin = origin
        self.dir = dir
    }

    var origin: SIMD3<Float>
    var dir: SIMD3<Float>
}

protocol RendererInputDelegate: AnyObject {
    func didMoveMouse(deltaX: Float, deltaY: Float)
    func didKeyDown(_ key: String)
    func didKeyUp(_ key: String)
}

class Renderer: NSObject, MTKViewDelegate, RendererInputDelegate {

    func didKeyUp(_ key: String) {
        print("key up: \(key)")
        switch key {
            case "w":
            isWKeyPressed = false
            print("W key released")
        case "s":
            isSKeyPressed = false
        case "a":
            isAKeyPressed = false
        case "d":
            isDKeyPressed = false
        default:
            break
        }
    }

    func didKeyDown(_ key: String) {
        switch key {
            case "w":
            isWKeyPressed = true
            print("W key pressed")
        case "s":
            isSKeyPressed = true
        case "a":
            isAKeyPressed = true
        case "d":
            isDKeyPressed = true
        default:
            break
        }
    }

    private var isWKeyPressed = false
    private var isSKeyPressed = false
    private var isAKeyPressed = false
    private var isDKeyPressed = false

    func didMoveMouse(deltaX: Float, deltaY: Float) {
        print(deltaX, deltaY)
        let xRot = matrix4x4_rotation(radians: -deltaX/200, axis: SIMD3<Float>(0, 1, 0))
        let yRot = matrix4x4_rotation(radians: deltaY/400, axis: SIMD3<Float>(1, 0, 0))
        self.camera.orientation = yRot * xRot * self.camera.orientation
        let ptr = cameraBuffer.contents().bindMemory(to: Camera.self, capacity: 1)
        ptr.pointee = camera
    }
    

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue

    private var sphereBuffer: MTLBuffer!
    private var sphereCountBuffer: MTLBuffer!
    private var cameraBuffer: MTLBuffer!
    private var outputTexture: MTLTexture!

    var pipelineState: MTLComputePipelineState

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()


    let spheres: [Sphere] = [ Sphere(position: SIMD3<Float>(0,0,-3), radius: 5),
                              Sphere(position: SIMD3<Float>(5,5,-10), radius: 10)]
    var camera = Camera(position: SIMD3<Float>(0, 0, 10),
                        orientation: camera_inital_transform(),
                        distanceToPlane: 10,
                        height: 40,
                        width: 40)
    @MainActor
    init?(metalKitView: TracerMTKView) {
        self.device = metalKitView.device! // MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device.makeCommandQueue()!

        metalKitView.framebufferOnly = false // required to allow us to write to drawbable from compute
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb



        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "raytrace")!
        self.pipelineState = try! device.makeComputePipelineState(function: function)

        super.init()

        self.sphereBuffer = self.device.makeBuffer(bytes: spheres, length: MemoryLayout<Sphere>.stride * spheres.count, options: [.storageModeShared])!
        var count = Int32(spheres.count)
        self.sphereCountBuffer = self.device.makeBuffer(bytes: &count, length: MemoryLayout<Int32>.stride, options: [.storageModeShared])
        self.cameraBuffer = self.device.makeBuffer(length: MemoryLayout<Camera>.stride, options: [.storageModeShared])!
        let ptr = cameraBuffer.contents().bindMemory(to: Camera.self, capacity: 1)
        ptr.pointee = camera

        // Output Offscreen buffer
        createOutputTexture(width: Int(metalKitView.drawableSize.width), height: Int(metalKitView.drawableSize.height))
    }


    func draw(in view: MTKView) {
// Camera update
        let cameraPointDir = SIMD3(camera.orientation.columns.2.x, camera.orientation.columns.2.y, camera.orientation.columns.2.z)
        let cameraLeftDir = SIMD3(camera.orientation.columns.0.x, camera.orientation.columns.0.y, camera.orientation.columns.0.z)
        if isWKeyPressed {
            self.camera.position = camera.position + 0.25 * cameraPointDir;
        }

        if isSKeyPressed {
            self.camera.position = camera.position - 0.25 * cameraPointDir;
        }

        if isDKeyPressed {
            self.camera.position = camera.position + 0.25 * cameraLeftDir;
        }

        if isAKeyPressed {
            self.camera.position = camera.position - 0.25 * cameraLeftDir;
        }
        let ptr = cameraBuffer.contents().bindMemory(to: Camera.self, capacity: 1)
        ptr.pointee = camera

        /// Per frame updates hare
        guard let drawable = view.currentDrawable,
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)

        // loading of our data
        encoder.setTexture(outputTexture, index: 0)
        encoder.setBuffer(sphereBuffer, offset: 0, index: 0)
        encoder.setBuffer(sphereCountBuffer, offset: 0, index: 1)
        encoder.setBuffer(cameraBuffer, offset: 0, index: 2)

//one thread per pixel
        let w = pipelineState.threadExecutionWidth // ussually 32 for apple gpus., some hardware properry on how wide things can be computed in paralell
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w // max num threads in a thread group for the kernel/device. usually 512 or 1024
        //we device by w to get h we have a 2D block (w x h)

        let tgSize = MTLSize(width: w, height: max(1, h), depth: 1) // defines thread group size, 2D shape since depth is 1.
        let grid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1) // defines number of threads to dispatch (one thread = 1 pixel)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize) // we could just have 1D shape...

        encoder.endEncoding()
        let start = CACurrentMediaTime()
        // submit command buffer
        commandBuffer.addCompletedHandler { _ in
            let duration = CACurrentMediaTime() - start
//            print("Shader 'frame' rate is: \(1 / duration) Hz")
        }
 // We blit the offscreen buffer to the screen
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
              blitEncoder.copy(from: outputTexture,
                               sourceSlice: 0,
                               sourceLevel: 0,
                               sourceOrigin: MTLOrigin(x:0,y:0,z:0),
                               sourceSize: MTLSize(width: outputTexture.width,
                                                   height: outputTexture.height,
                                                   depth: 1),
                               to: drawable.texture,
                               destinationSlice: 0,
                               destinationLevel: 0,
                               destinationOrigin: MTLOrigin(x:0,y:0,z:0))
              blitEncoder.endEncoding()
          }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        createOutputTexture(width: Int(size.width), height: Int(size.height))
    }

    func createOutputTexture(width: Int, height: Int) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        outputTexture = device.makeTexture(descriptor: desc)
    }

    func mtkView(_ view: MTKView, mouseMoved event: NSEvent) {
        print("recieved")
    }
}



// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func camera_inital_transform() -> matrix_float4x4 {
    var mat = matrix4x4_translation(0, 0, -10)
    mat.columns.2.z = -1 // flip the z
    return mat
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
