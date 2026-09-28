import Foundation
import Testing
@testable import CleanCutKit

@Suite("Recipe")
struct RecipeTests {
    @Test func codableRoundTripPreservesEveryField() throws {
        let recipe = Recipe(
            selectedInstances: [1, 3],
            background: .studioSweep(RGBA(hex: 0xF3EEE6)),
            shadow: ShadowStyle(kind: .soft, intensity: 0.4, angle: 300, distance: 0.1, softness: 0.08),
            edges: EdgeSettings(feather: 0.01, cleanEdges: false, cleanStrength: 0.5),
            presetID: .vinted
        )
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        #expect(decoded == recipe)
    }

    @Test func defaultRecipeIsAStudioWhiteNaturalShadowLook() {
        let recipe = Recipe.default
        #expect(recipe.selectedInstances == nil)
        #expect(recipe.background == .solid(.white))
        #expect(recipe.shadow.kind == .natural)
        #expect(recipe.edges.cleanEdges)
    }

    @Test func clampingKeepsParametersInRange() {
        var recipe = Recipe.default
        recipe.shadow.intensity = 4
        recipe.shadow.distance = -1
        recipe.shadow.softness = 0
        recipe.shadow.angle = -90
        recipe.edges.feather = 1
        recipe.edges.cleanStrength = -3

        let clamped = recipe.clamped()
        #expect(clamped.shadow.intensity == 1)
        #expect(clamped.shadow.distance == 0)
        #expect(clamped.shadow.softness == ShadowStyle.softnessRange.lowerBound)
        #expect(clamped.shadow.angle == 270)
        #expect(clamped.edges.feather == EdgeSettings.featherRange.upperBound)
        #expect(clamped.edges.cleanStrength == 0)
    }

    @Test func amazonForcesPureWhiteBackground() {
        let recipe = Recipe(background: .studioSweep(RGBA(hex: 0x223344)), presetID: .amazon)
        #expect(recipe.effectiveBackground == .solid(.white))
    }

    @Test func cutoutForcesTransparency() {
        let recipe = Recipe(background: .solid(.black), presetID: .cutout)
        #expect(recipe.effectiveBackground == .transparent)
        #expect(recipe.preset.supportsTransparency)
    }

    @Test func freeformPresetsKeepTheChosenBackground() {
        let color = BackgroundStyle.solid(RGBA(hex: 0xEEEEEE))
        #expect(Recipe(background: color, presetID: .depop).effectiveBackground == color)
        #expect(Recipe(background: color, presetID: .vinted).effectiveBackground == color)
    }
}

@Suite("RGBA")
struct RGBATests {
    @Test func hexLiteralDecodesChannels() {
        let color = RGBA(hex: 0xFF8000)
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255) < 1e-9)
        #expect(color.blue == 0)
    }

    @Test func initClampsComponents() {
        let color = RGBA(red: 2, green: -1, blue: 0.5, alpha: 7)
        #expect(color == RGBA(red: 1, green: 0, blue: 0.5, alpha: 1))
    }

    @Test func brightnessMovesTowardWhiteOrBlack() {
        let gray = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.adjustingBrightness(1) == .white)
        #expect(gray.adjustingBrightness(-1) == .black)
        #expect(gray.adjustingBrightness(0.5).red == 0.75)
    }
}

@Suite("History")
struct HistoryTests {
    @Test func undoAndRedoWalkThroughCommittedValues() {
        var history = History(0)
        history.commit(1)
        history.commit(2)
        #expect(history.undo() == 1)
        #expect(history.undo() == 0)
        #expect(history.undo() == nil)
        #expect(history.redo() == 1)
        #expect(history.current == 1)
    }

    @Test func committingAfterUndoDropsTheRedoBranch() {
        var history = History("a")
        history.commit("b")
        history.undo()
        history.commit("c")
        #expect(!history.canRedo)
        #expect(history.undo() == "a")
    }

    @Test func committingTheSameValueIsANoOp() {
        var history = History(5)
        history.commit(5)
        #expect(!history.canUndo)
    }

    @Test func limitDropsTheOldestSteps() {
        var history = History(0, limit: 3)
        for value in 1...10 { history.commit(value) }
        var undone: [Int] = []
        while let value = history.undo() { undone.append(value) }
        #expect(undone == [9, 8, 7])
    }
}
