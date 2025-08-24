//
//  Renderer.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

// Our platform independent renderer class

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
    var direction: SIMD3<Float>
    var distanceToPlane: Float
    var height: Float
    var width: Float

    init(position: SIMD3<Float>, direction: SIMD3<Float>, distanceToPlane: Float, height: Float, width: Float) {
        self.position = position
        self.direction = direction
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

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue

    private var sphereBuffer: MTLBuffer!
    private var sphereCountBuffer: MTLBuffer!
    private var cameraBuffer: MTLBuffer!

    var pipelineState: MTLComputePipelineState



//    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()


    let spheres: [Sphere] = [ Sphere(position: SIMD3<Float>(0,0,-3), radius: 5),
                              Sphere(position: SIMD3<Float>(5,5,-10), radius: 10)]
    let camera = Camera(position: SIMD3<Float>(0, 0, 5),
                        direction: SIMD3<Float>(0, 0, -1),
                        distanceToPlane: 5,
                        height: 30,
                        width: 30)
    @MainActor
    init?(metalKitView: MTKView) {
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
    }


    func draw(in view: MTKView) {
        /// Per frame updates hare
        guard let drawable = view.currentDrawable,
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)

        // loading of our data
        encoder.setTexture(drawable.texture, index: 0)
        encoder.setBuffer(sphereBuffer, offset: 0, index: 0)
        encoder.setBuffer(sphereCountBuffer, offset: 0, index: 1)
        encoder.setBuffer(cameraBuffer, offset: 0, index: 2)

//one thread per pixel
        let w = pipelineState.threadExecutionWidth // ussually 32 for apple gpus., some hardware properry on how wide things can be computed in paralell
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w // max num threads in a thread group for the kernel/device. usually 512 or 1024
        //we device by w to get h we have a 2D block (w x h)

        let tgSize = MTLSize(width: w, height: max(1, h), depth: 1) // defines thread group size, 2D shape since depth is 1.
        let grid = MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1) // defines number of threads to dispatch (one thread = 1 pixel)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize) // we could just have 1D shape...

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
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
