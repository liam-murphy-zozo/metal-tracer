//
//  Renderer.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/24.
//

// TODO LIST:
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

protocol RendererInputDelegate: AnyObject {
    func didMoveMouse(deltaX: Float, deltaY: Float)
    func didKeyDown(_ key: String)
    func didKeyUp(_ key: String)
}

class Renderer: NSObject, MTKViewDelegate, RendererInputDelegate {

    private var isWKeyPressed = false
    private var isSKeyPressed = false
    private var isAKeyPressed = false
    private var isDKeyPressed = false

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var scene: Scene
    private var sceneUniformBuffer: MTLBuffer!
    private var sphereBuffer: MTLBuffer!
    private var outputTexture: MTLTexture!

    var pipelineState: MTLComputePipelineState

    @MainActor
    init?(metalKitView: TracerMTKView) {
        self.device = metalKitView.device! // MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device.makeCommandQueue()!

        metalKitView.framebufferOnly = false // required to allow us to write to drawbable from compute
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb

        scene = createScene()

        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "raytrace")!
        self.pipelineState = try! device.makeComputePipelineState(function: function)

        super.init()
        self.sceneUniformBuffer = self.device.makeBuffer(length: MemoryLayout<SceneUniform>.stride, options: [.storageModeShared])
        let scenePtr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        scenePtr.pointee = scene.sceneUniform

        self.sphereBuffer = self.device.makeBuffer(bytes: scene.spheres, length: MemoryLayout<Sphere>.stride * scene.spheres.count, options: [.storageModeShared])!

        // Output Offscreen buffer
        createOutputTexture(width: Int(metalKitView.drawableSize.width), height: Int(metalKitView.drawableSize.height))
    }


    func draw(in view: MTKView) {
        // Camera update
        let cameraPointDir = scene.sceneUniform.camera.orientation.get2XYZ()
        let cameraLeftDir = scene.sceneUniform.camera.orientation.get0XYZ()
        let speed: Float = 0.25
        if isWKeyPressed {
            scene.sceneUniform.camera.position += (speed * cameraPointDir);
        }
        if isSKeyPressed {
            scene.sceneUniform.camera.position -= (speed * cameraPointDir);
        }
        if isDKeyPressed {
            scene.sceneUniform.camera.position += (speed * cameraLeftDir);
        }
        if isAKeyPressed {
            scene.sceneUniform.camera.position -=  (speed * cameraLeftDir);
        }
        let ptr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        ptr.pointee = scene.sceneUniform

        /// Per frame updates hare
        guard let drawable = view.currentDrawable,
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)

        // loading of our data
        encoder.setTexture(outputTexture, index: 0)
        encoder.setBuffer(sceneUniformBuffer, offset: 0, index: 0)
        encoder.setBuffer(sphereBuffer, offset: 0, index: 1)

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
            print("Shader 'frame' rate is: \(1 / duration) Hz")
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

    // keyboard input / mouse input delegate implementation
    func didKeyUp(_ key: String) {
        switch key {
            case "w":
            isWKeyPressed = false
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

    func didMoveMouse(deltaX: Float, deltaY: Float) {
        let upAxis = scene.sceneUniform.camera.orientation.get1XYZ()
        let leftAxis = scene.sceneUniform.camera.orientation.get0XYZ()
        let xRot = matrix4x4_rotation(radians: -deltaX/250, axis: upAxis)
        let yRot = matrix4x4_rotation(radians: deltaY/250, axis: leftAxis)
        self.scene.sceneUniform.camera.orientation = yRot * xRot * self.scene.sceneUniform.camera.orientation
        let ptr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        ptr.pointee = self.scene.sceneUniform
    }
}

func createScene() -> Scene {
    let spheres: [Sphere] = [ Sphere(position: SIMD3<Float>(0,0,-3), radius: 5, color: SIMD3<Float>(0.5, 0.5, 0)),
                              Sphere(position: SIMD3<Float>(15,8,-10), radius: 10, color: SIMD3<Float>(0, 0.5, 0.5)),
                              Sphere(position: SIMD3<Float>(-10,-5,-10), radius: 7, color: SIMD3<Float>(0, 0.5, 0.0)),
                              Sphere(position: SIMD3<Float>(-10, 540,-100), radius: 500, color: SIMD3<Float>(1, 1, 1.0))]
    let camera = Camera(position: SIMD3<Float>(0, 0, 20),
                        orientation: camera_inital_transform(),
                        distanceToPlane: 50,
                        height: 40,
                        width: 40)

    let sceneUniform = SceneUniform(camera: camera, lightPosition: SIMD3<Float>(0, 0, 20), numSpheres: Int32(spheres.count))
    return Scene(sceneUniform: sceneUniform, spheres: spheres)
}

