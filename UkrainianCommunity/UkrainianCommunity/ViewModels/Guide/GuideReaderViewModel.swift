import Combine
import Foundation

enum GuideReaderEmptyState: Equatable {
    case noCategorySelected
    case noRootNodes(category: GuideCategory)
    case noNodeContent(nodeTitle: String)
}

enum GuideVisibleSection: Equatable {
    case childNodes([GuideNode])
    case materials([GuideMaterial])
}

struct GuideSearchResults: Equatable {
    let categories: [GuideCategory]
    let nodes: [GuideNode]
    let materials: [GuideMaterial]

    static let empty = GuideSearchResults(
        categories: [],
        nodes: [],
        materials: []
    )

    var isEmpty: Bool {
        categories.isEmpty && nodes.isEmpty && materials.isEmpty
    }
}

@MainActor
final class GuideReaderViewModel: ObservableObject {
    @Published private(set) var selectedCategory: GuideCategory?
    @Published private(set) var selectedFederalState: AustrianFederalState?
    @Published private(set) var currentNode: GuideNode?
    @Published private(set) var rootNodes: [GuideNode] = []
    @Published private(set) var childNodes: [GuideNode] = []
    @Published private(set) var materials: [GuideMaterial] = []
    @Published private(set) var savedMaterialIDs: Set<String> = []
    @Published private(set) var savedMaterials: [GuideMaterial] = []
    @Published private(set) var isLoadingSavedMaterials = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: GuideRepositoryProtocol

    private var rootNodesByCategory: [GuideCategoryCacheKey: [GuideNode]] = [:]
    private var childNodesByParentID: [NodeRegionCacheKey: [GuideNode]] = [:]
    private var materialsByNodeID: [NodeRegionCacheKey: [GuideMaterial]] = [:]
    private var materialByID: [String: GuideMaterial] = [:]
    private var nodeByID: [String: GuideNode] = [:]
    private var breadcrumbComponents: [GuideTreePath.Component] = []
    private var profileFederalState: AustrianFederalState?
    private var hasManualRegionOverride = false
    private var searchableNodesByRegion: [RegionCacheKey: [GuideNode]] = [:]
    private var searchableMaterialsByRegion: [RegionCacheKey: [GuideMaterial]] = [:]
    private var savedMaterialIDOrder: [String] = []
    private var hasLoadedSavedMaterialIDs = false
    private var pendingSavedMaterialIDs = Set<String>()

    init(repository: GuideRepositoryProtocol) {
        self.repository = repository
    }

    func makeChildViewModel() -> GuideReaderViewModel {
        let childViewModel = GuideReaderViewModel(repository: repository)
        childViewModel.selectedFederalState = selectedFederalState
        childViewModel.profileFederalState = profileFederalState
        childViewModel.hasManualRegionOverride = hasManualRegionOverride
        childViewModel.rootNodesByCategory = rootNodesByCategory
        childViewModel.childNodesByParentID = childNodesByParentID
        childViewModel.materialsByNodeID = materialsByNodeID
        childViewModel.searchableNodesByRegion = searchableNodesByRegion
        childViewModel.searchableMaterialsByRegion = searchableMaterialsByRegion
        childViewModel.materialByID = materialByID
        childViewModel.nodeByID = nodeByID
        childViewModel.savedMaterialIDs = savedMaterialIDs
        childViewModel.savedMaterials = savedMaterials
        childViewModel.savedMaterialIDOrder = savedMaterialIDOrder
        childViewModel.hasLoadedSavedMaterialIDs = hasLoadedSavedMaterialIDs
        childViewModel.pendingSavedMaterialIDs = pendingSavedMaterialIDs
        return childViewModel
    }

    var breadcrumbs: GuideTreePath {
        GuideTreePath(components: breadcrumbComponents)
    }

    var visibleChildNodes: [GuideNode] {
        currentNode == nil ? rootNodes : childNodes
    }

    var visibleMaterials: [GuideMaterial] {
        materials
    }

    var visibleSections: [GuideVisibleSection] {
        var sections: [GuideVisibleSection] = []

        if !visibleChildNodes.isEmpty {
            sections.append(.childNodes(visibleChildNodes))
        }

        if !visibleMaterials.isEmpty {
            sections.append(.materials(visibleMaterials))
        }

        return sections
    }

    var hasContent: Bool {
        !visibleChildNodes.isEmpty || !visibleMaterials.isEmpty
    }

    var emptyState: GuideReaderEmptyState {
        if let currentNode, !hasContent {
            return .noNodeContent(nodeTitle: currentNode.title)
        }

        if let selectedCategory, rootNodes.isEmpty {
            return .noRootNodes(category: selectedCategory)
        }

        return .noCategorySelected
    }

    func selectCategory(_ category: GuideCategory) async {
        await loadCategory(category, force: false)
    }

    func openNode(_ node: GuideNode) async {
        await loadNode(node, force: false)
    }

    func goBackToBreadcrumb(_ component: GuideTreePath.Component) async {
        guard let selectedCategory else { return }

        if component.id == selectedCategory.rawValue {
            await loadCategory(selectedCategory, force: false)
            return
        }

        guard let node = nodeByID[component.id] else {
            error = .notFound
            return
        }

        await loadNode(node, force: false, breadcrumbOverride: pathComponents(to: node))
    }

    func reload() async {
        if let currentNode {
            await loadNode(currentNode, force: true)
        } else if let selectedCategory {
            await loadCategory(selectedCategory, force: true)
        }
    }

    func syncProfileFederalState(_ federalState: AustrianFederalState?) async {
        profileFederalState = federalState

        guard !hasManualRegionOverride else { return }
        guard selectedFederalState != federalState else { return }

        selectedFederalState = federalState
        await reload()
    }

    func selectFederalState(_ federalState: AustrianFederalState?) async {
        let nextManualOverride = federalState != profileFederalState

        guard selectedFederalState != federalState || hasManualRegionOverride != nextManualOverride else {
            return
        }

        hasManualRegionOverride = nextManualOverride
        selectedFederalState = federalState
        await reload()
    }

    func searchResults(for query: String) async throws -> GuideSearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .empty
        }

        let searchableNodes = try await fetchSearchableNodes()
        let searchableMaterials = try await fetchSearchableMaterials()

        let categories = GuideCategoryPresentation.publicTopLevelCategories.filter { category in
            LocalSearchMatcher.matches(
                query: trimmedQuery,
                values: [
                    GuideCategoryPresentation.publicTitle(for: category),
                    GuideCategoryPresentation.subtitle(for: category)
                ]
            )
        }

        let nodes = searchableNodes.filter { node in
            LocalSearchMatcher.matches(
                query: trimmedQuery,
                values: [node.title, node.summary]
            )
        }

        let materials = searchableMaterials.filter { material in
            LocalSearchMatcher.matches(
                query: trimmedQuery,
                values: materialSearchableValues(for: material)
            )
        }

        return GuideSearchResults(
            categories: categories,
            nodes: nodes,
            materials: materials
        )
    }

    func loadSavedMaterialsIfNeeded() async {
        guard !hasLoadedSavedMaterialIDs else { return }
        await refreshSavedMaterials()
    }

    func refreshSavedMaterials() async {
        isLoadingSavedMaterials = true
        defer { isLoadingSavedMaterials = false }

        do {
            let ids = try await repository.fetchSavedMaterialIDs()
            hasLoadedSavedMaterialIDs = true
            savedMaterialIDOrder = ids
            savedMaterialIDs = Set(ids)
            savedMaterials = try await resolveSavedMaterials(for: ids)
            error = nil
        } catch {
            handle(error)
        }
    }

    func resetSavedMaterialsState() {
        savedMaterialIDs = []
        savedMaterials = []
        savedMaterialIDOrder = []
        hasLoadedSavedMaterialIDs = false
        pendingSavedMaterialIDs = []
    }

    func isMaterialSaved(_ materialID: String) -> Bool {
        savedMaterialIDs.contains(materialID)
    }

    func isMaterialSavePending(_ materialID: String) -> Bool {
        pendingSavedMaterialIDs.contains(materialID)
    }

    func toggleSavedMaterial(_ material: GuideMaterial) async throws {
        let shouldSave = !savedMaterialIDs.contains(material.id)
        let previousIDs = savedMaterialIDs
        let previousOrder = savedMaterialIDOrder
        let previousMaterials = savedMaterials

        applyOptimisticSavedState(for: material, shouldSave: shouldSave)
        pendingSavedMaterialIDs.insert(material.id)
        defer { pendingSavedMaterialIDs.remove(material.id) }

        do {
            if shouldSave {
                try await repository.bookmarkMaterial(id: material.id)
            } else {
                try await repository.unbookmarkMaterial(id: material.id)
            }
            hasLoadedSavedMaterialIDs = true
            error = nil
        } catch {
            savedMaterialIDs = previousIDs
            savedMaterialIDOrder = previousOrder
            savedMaterials = previousMaterials
            throw error
        }
    }

    private func loadCategory(_ category: GuideCategory, force: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let nodes = try await fetchRootNodes(for: category, force: force)
            selectedCategory = category
            currentNode = nil
            rootNodes = nodes
            childNodes = []
            materials = []
            breadcrumbComponents = [GuideTreePath.Component(id: category.rawValue, title: GuideCategoryPresentation.publicTitle(for: category))]
            error = nil
        } catch {
            handle(error)
        }
    }

    private func loadNode(
        _ node: GuideNode,
        force: Bool,
        breadcrumbOverride: [GuideTreePath.Component]? = nil
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let childNodes = try await fetchChildNodes(for: node.id, force: force)
            let materials = try await fetchMaterials(for: node.id, force: force)

            selectedCategory = node.category
            currentNode = node
            rootNodes = rootNodesForCurrentCategory(fallbackCategory: node.category)
            self.childNodes = childNodes
            self.materials = materials
            breadcrumbComponents = breadcrumbOverride ?? pathComponents(to: node)
            error = nil
        } catch {
            handle(error)
        }
    }

    private func fetchRootNodes(for category: GuideCategory, force: Bool) async throws -> [GuideNode] {
        let cacheKey = GuideCategoryCacheKey(
            category: category,
            federalState: selectedFederalState
        )

        if !force, let cachedNodes = rootNodesByCategory[cacheKey] {
            return cachedNodes
        }

        let nodes = try await repository.fetchRootNodes(
            category: category,
            selectedFederalState: selectedFederalState
        )
        rootNodesByCategory[cacheKey] = nodes
        cache(nodes: nodes)
        return nodes
    }

    private func fetchChildNodes(for parentID: String, force: Bool) async throws -> [GuideNode] {
        let cacheKey = NodeRegionCacheKey(
            nodeID: parentID,
            federalState: selectedFederalState
        )

        if !force, let cachedNodes = childNodesByParentID[cacheKey] {
            return cachedNodes
        }

        let nodes = try await repository.fetchChildNodes(
            parentId: parentID,
            selectedFederalState: selectedFederalState
        )
        childNodesByParentID[cacheKey] = nodes
        cache(nodes: nodes)
        return nodes
    }

    private func fetchMaterials(for nodeID: String, force: Bool) async throws -> [GuideMaterial] {
        let cacheKey = NodeRegionCacheKey(
            nodeID: nodeID,
            federalState: selectedFederalState
        )

        if !force, let cachedMaterials = materialsByNodeID[cacheKey] {
            return cachedMaterials
        }

        let materials = try await repository.fetchMaterials(
            nodeId: nodeID,
            selectedFederalState: selectedFederalState
        )
        materialsByNodeID[cacheKey] = materials
        cache(materials: materials)
        return materials
    }

    private func cache(nodes: [GuideNode]) {
        for node in nodes {
            nodeByID[node.id] = node
        }
    }

    private func cache(materials: [GuideMaterial]) {
        for material in materials {
            materialByID[material.id] = material
        }
    }

    private func fetchSearchableNodes() async throws -> [GuideNode] {
        let cacheKey = RegionCacheKey(federalState: selectedFederalState)
        if let cachedNodes = searchableNodesByRegion[cacheKey] {
            return cachedNodes
        }

        let nodes = try await repository.fetchAllNodesForSearch(
            selectedFederalState: selectedFederalState
        )
        searchableNodesByRegion[cacheKey] = nodes
        cache(nodes: nodes)
        return nodes
    }

    private func fetchSearchableMaterials() async throws -> [GuideMaterial] {
        let cacheKey = RegionCacheKey(federalState: selectedFederalState)
        if let cachedMaterials = searchableMaterialsByRegion[cacheKey] {
            return cachedMaterials
        }

        let materials = try await repository.fetchAllMaterialsForSearch(
            selectedFederalState: selectedFederalState
        )
        searchableMaterialsByRegion[cacheKey] = materials
        cache(materials: materials)
        return materials
    }

    private func resolveSavedMaterials(for ids: [String]) async throws -> [GuideMaterial] {
        let cachedMaterialsByID = ids.reduce(into: [String: GuideMaterial]()) { partialResult, id in
            if let material = materialByID[id] {
                partialResult[id] = material
            }
        }

        let missingIDs = ids.filter { cachedMaterialsByID[$0] == nil }
        let fetchedMaterialsByID = try await fetchMaterialsByID(ids: missingIDs)
        cache(materials: Array(fetchedMaterialsByID.values))

        let combinedMaterialsByID = cachedMaterialsByID.merging(fetchedMaterialsByID) { current, _ in current }
        return ids.compactMap { combinedMaterialsByID[$0] }
    }

    private func fetchMaterialsByID(ids: [String]) async throws -> [String: GuideMaterial] {
        guard !ids.isEmpty else { return [:] }

        var materialsByID: [String: GuideMaterial] = [:]

        try await withThrowingTaskGroup(of: (String, GuideMaterial?).self) { group in
            for id in ids {
                group.addTask {
                    do {
                        return (id, try await self.repository.fetchMaterial(id: id))
                    } catch let appError as AppError where appError == .notFound {
                        return (id, nil)
                    }
                }
            }

            for try await (id, material) in group {
                if let material {
                    materialsByID[id] = material
                }
            }
        }

        return materialsByID
    }

    private func rootNodesForCurrentCategory(fallbackCategory: GuideCategory) -> [GuideNode] {
        let category = selectedCategory ?? fallbackCategory
        let cacheKey = GuideCategoryCacheKey(
            category: category,
            federalState: selectedFederalState
        )
        return rootNodesByCategory[cacheKey] ?? []
    }

    private func pathComponents(to node: GuideNode) -> [GuideTreePath.Component] {
        var components = [GuideTreePath.Component(id: node.category.rawValue, title: GuideCategoryPresentation.publicTitle(for: node.category))]

        var lineage = [GuideTreePath.Component(id: node.id, title: node.title)]
        var cursor = node

        while let parentID = cursor.parentID, let parentNode = nodeByID[parentID] {
            lineage.append(GuideTreePath.Component(id: parentNode.id, title: parentNode.title))
            cursor = parentNode
        }

        components.append(contentsOf: lineage.reversed())
        return components
    }

    private func materialSearchableValues(for material: GuideMaterial) -> [String?] {
        var values: [String?] = [
            material.title,
            material.summary,
            material.body
        ]
        values.append(contentsOf: material.contentBlocks.flatMap(\.searchableTextValues))
        values.append(contentsOf: material.sourceLinks.flatMap(\.searchableTextValues))
        values.append(material.officialSourceURL)
        values.append(material.sourceName)
        return values
    }

    private func applyOptimisticSavedState(
        for material: GuideMaterial,
        shouldSave: Bool
    ) {
        if shouldSave {
            savedMaterialIDs.insert(material.id)
            savedMaterialIDOrder.removeAll { $0 == material.id }
            savedMaterialIDOrder.insert(material.id, at: 0)
            savedMaterials.removeAll { $0.id == material.id }
            savedMaterials.insert(material, at: 0)
        } else {
            savedMaterialIDs.remove(material.id)
            savedMaterialIDOrder.removeAll { $0 == material.id }
            savedMaterials.removeAll { $0.id == material.id }
        }
    }

    private func handle(_ error: Error) {
        if let appError = error as? AppError {
            self.error = appError
        } else {
            self.error = .unknown
        }
    }
}

private struct GuideCategoryCacheKey: Hashable {
    let category: GuideCategory
    let federalState: AustrianFederalState?
}

private struct NodeRegionCacheKey: Hashable {
    let nodeID: String
    let federalState: AustrianFederalState?
}

private struct RegionCacheKey: Hashable {
    let federalState: AustrianFederalState?
}
