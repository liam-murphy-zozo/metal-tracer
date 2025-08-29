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
    private var mouseXRad = Float.zero
    private var mouseYRad = Float.zero
    private var didCameraChange = false

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var scene: Scene
    private var sceneUniformBuffer: MTLBuffer!
    private var sphereBuffer: MTLBuffer!
    private var planeBuffer: MTLBuffer!
    private var discBuffer: MTLBuffer!

    private var outputTexture: MTLTexture!
    private var accumulationTexture: MTLTexture!

    var pipelineState: MTLComputePipelineState
    var postProcPipelineState: MTLComputePipelineState

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

        let postProcFunc = library.makeFunction(name: "postProcess")!
        self.postProcPipelineState = try! device.makeComputePipelineState(function: postProcFunc)
        super.init()
        self.sceneUniformBuffer = self.device.makeBuffer(length: MemoryLayout<SceneUniform>.stride, options: [.storageModeShared])
        let scenePtr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        scenePtr.pointee = scene.sceneUniform

        self.sphereBuffer = self.device.makeBuffer(bytes: scene.spheres, length: MemoryLayout<Sphere>.stride * Int(scene.sceneUniform.numSpheres), options: [.storageModeShared])!

        self.planeBuffer = self.device.makeBuffer(bytes: scene.planes, length: MemoryLayout<Plane>.stride * Int(scene.sceneUniform.numPlanes), options: [.storageModeShared])!

        self.discBuffer = self.device.makeBuffer(bytes: scene.discs, length: MemoryLayout<Disc>.stride * Int(scene.sceneUniform.numDiscs), options: [.storageModeShared])!

        // Output Offscreen buffer
        createOutputTexture(width: Int(metalKitView.drawableSize.width), height: Int(metalKitView.drawableSize.height))
    }


    func draw(in view: MTKView) {
        scene.sceneUniform.frameIndex += 1
        // Camera update
        let cameraPointDir = scene.sceneUniform.camera.orientation.get2XYZ()
        let cameraLeftDir = scene.sceneUniform.camera.orientation.get0XYZ()
        let speed: Float = 0.25

        if isWKeyPressed {
            scene.sceneUniform.camera.position += (speed * cameraPointDir);
            scene.sceneUniform.didChangeCamera = true
        }
        if isSKeyPressed {
            scene.sceneUniform.camera.position -= (speed * cameraPointDir);
            scene.sceneUniform.didChangeCamera = true
        }
        if isDKeyPressed {
            scene.sceneUniform.camera.position += (speed * cameraLeftDir);
            scene.sceneUniform.didChangeCamera = true
        }
        if isAKeyPressed {
            scene.sceneUniform.camera.position -=  (speed * cameraLeftDir);
            scene.sceneUniform.didChangeCamera = true
        }
        let ptr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        ptr.pointee = scene.sceneUniform

        /// Per frame updates hare
        guard
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipelineState)

        // loading of our data
        encoder.setTexture(accumulationTexture, index: 0)
        encoder.setTexture(accumulationTexture, index: 1)
        encoder.setBuffer(sceneUniformBuffer, offset: 0, index: 0)
        encoder.setBuffer(sphereBuffer, offset: 0, index: 1)
        encoder.setBuffer(planeBuffer, offset: 0, index: 2)
        encoder.setBuffer(discBuffer, offset: 0, index: 3)

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

        guard let drawable = view.currentDrawable,
        let postProcEncoder = commandBuffer.makeComputeCommandEncoder() else {return}
        postProcEncoder.setComputePipelineState(postProcPipelineState)
        postProcEncoder.setTexture(accumulationTexture, index: 0)
        postProcEncoder.setTexture(outputTexture, index: 1)
        postProcEncoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        postProcEncoder.endEncoding()


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

        scene.sceneUniform.didChangeCamera = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        createOutputTexture(width: Int(size.width), height: Int(size.height))
    }

    func createOutputTexture(width: Int, height: Int) {
        // output texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        outputTexture = device.makeTexture(descriptor: desc)

        // accumulation texture
        let accumDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        accumDesc.usage = [.shaderWrite, .shaderRead, .renderTarget]
        accumDesc.storageMode = .private
        accumulationTexture = device.makeTexture(descriptor: accumDesc)

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
        mouseXRad = remainder((mouseXRad - deltaX/250),(2*Float.pi))
        mouseYRad = remainder((mouseYRad + deltaY/250),(2*Float.pi))
        let originalMatrix = camera_inital_transform()
        let upAxis = originalMatrix.get1XYZ()
        let leftAxis = originalMatrix.get0XYZ()
        let xRot = matrix4x4_rotation(radians: mouseXRad, axis: upAxis)
        let yRot = matrix4x4_rotation(radians: mouseYRad, axis: leftAxis)
        self.scene.sceneUniform.camera.orientation =  xRot * yRot * originalMatrix
        let ptr = sceneUniformBuffer.contents().bindMemory(to: SceneUniform.self, capacity: 1)
        ptr.pointee = self.scene.sceneUniform
        scene.sceneUniform.didChangeCamera = true
    }
}

func createScene() -> Scene {
    let spheres: [Sphere] = [ Sphere(position: SIMD3<Float>(0,0,-2), radius: 2, color: SIMD3<Float>(0.5, 0.5, 0)),
                              Sphere(position: SIMD3<Float>(1,2,0), radius: 0.7, color: SIMD3<Float>(0, 0.5, 0.5)),
                              Sphere(position: SIMD3<Float>(-2,-2,-3.1), radius: 1.2, color: SIMD3<Float>(0, 0.5, 0.0))]

    let planes: [Plane] = [Plane(position: SIMD3<Float>(0,3,0), normal: SIMD3<Float>(0,-1,0), color: SIMD3<Float>(0.5,0.5,0.5)),
                           Plane(position: SIMD3<Float>(0,-4,0), normal: SIMD3<Float>(0,1,0), color: SIMD3<Float>(0.5,0.5,0.5)),
                           Plane(position: SIMD3<Float>(4,0,0), normal: SIMD3<Float>(-1,0,0), color: SIMD3<Float>(0.75,0,0)),
                           Plane(position: SIMD3<Float>(-4,0,0), normal: SIMD3<Float>(1,0,0), color: SIMD3<Float>(0,0.75,0)),
                           Plane(position: SIMD3<Float>(0,0,-5), normal: SIMD3<Float>(0,0,1), color: SIMD3<Float>(0.5,0.5,0.5))]
    let discs: [Disc] = [Disc(position: SIMD3<Float>(0,-3.9,0), normal: SIMD3<Float>(0,1,0), color: SIMD3<Float>(1,1,1), radius: 1)]
    let camera = Camera(position: SIMD3<Float>(0, 0, 20),
                        orientation: camera_inital_transform(),
                        distanceToPlane: 50,
                        height: 40,
                        width: 40)

    let sceneUniform = SceneUniform(camera: camera,
                                    numSpheres: Int32(spheres.count),
                                    numPlanes: Int32(planes.count),
                                    numDiscs: Int32(discs.count),
                                    frameIndex: 0,
                                    didChangeCamera: false);
    return Scene(sceneUniform: sceneUniform, spheres: spheres, planes: planes, discs: discs)
}

