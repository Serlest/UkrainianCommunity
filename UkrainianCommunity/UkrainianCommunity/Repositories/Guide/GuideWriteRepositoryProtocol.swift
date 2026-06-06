import Foundation

struct GuideSortOrderUpdate: Equatable {
    let id: String
    let sortOrder: Int
}

enum GuideReorderDirection {
    case up
    case down
}

protocol GuideWriteRepositoryProtocol {
    func hasAnyChildNodes(parentId: String) async throws -> Bool
    func hasAnyMaterials(nodeId: String) async throws -> Bool

    func createRootNode(_ node: GuideNode) async throws -> GuideNode
    func createChildNode(_ node: GuideNode) async throws -> GuideNode
    func updateNode(_ node: GuideNode) async throws
    func updateNodeSortOrders(_ updates: [GuideSortOrderUpdate], updatedAt: Date, updatedBy: String?) async throws
    func deleteNode(id: String) async throws
    func archiveNode(id: String, archivedAt: Date, updatedBy: String?) async throws
    func publishNode(id: String, publishedAt: Date, updatedBy: String?) async throws

    func createMaterial(_ material: GuideMaterial) async throws -> GuideMaterial
    func updateMaterial(_ material: GuideMaterial) async throws
    func updateMaterialSortOrders(_ updates: [GuideSortOrderUpdate], updatedAt: Date, updatedBy: String?) async throws
    func deleteMaterial(id: String) async throws
    func archiveMaterial(id: String, archivedAt: Date, updatedBy: String?) async throws
    func publishMaterial(id: String, publishedAt: Date, updatedBy: String?) async throws
    func markMaterialReviewed(
        id: String,
        reviewedAt: Date,
        nextReviewAt: Date,
        reviewedBy: String?
    ) async throws
}
