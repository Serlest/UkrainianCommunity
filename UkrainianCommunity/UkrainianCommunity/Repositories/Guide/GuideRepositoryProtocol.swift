import Foundation

protocol GuideRepositoryProtocol {
    func fetchRootNodes(
        category: GuideCategory,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode]
    func fetchChildNodes(
        parentId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode]
    func fetchMaterials(
        nodeId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial]
    func fetchAllNodesForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode]
    func fetchAllMaterialsForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial]
    func fetchMaterialsNeedingReview() async throws -> [GuideMaterial]
    func fetchSavedMaterialIDs() async throws -> [String]
    func bookmarkMaterial(id: String) async throws
    func unbookmarkMaterial(id: String) async throws
    func fetchMaterial(id: String) async throws -> GuideMaterial
}
