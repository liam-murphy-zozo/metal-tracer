//
//  helpers.swift
//  metalRay
//
//  Created by Liam Murphy on 2025/08/26.
//


import simd
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

extension matrix_float4x4 {

    func get0XYZ() -> SIMD3<Float> {
        return SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)
    }

    func get1XYZ() -> SIMD3<Float> {
        return SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z)
    }

    func get2XYZ() -> SIMD3<Float> {
        return SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
    }

    func get3XYZ() -> SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
