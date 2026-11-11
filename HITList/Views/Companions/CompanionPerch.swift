import SwiftUI

/// Where the companion lives, placed with one overlay line in the view that hosts it (briefs 76 and 79):
/// `.overlay(alignment: CompanionPerch.alignment(.searchField)) { CompanionPerch(.searchField) }`. One place per
/// platform, the same for every companion: the Mac sidebar's search field, at its right-hand middle; the "+" on
/// iPhone and iPad, at its top right (it goes with the "+" when a card opens and comes back with it). Which
/// companion is the theme's (`CompanionCast`).
///
/// It never changes its host's layout (it is drawn with an offset), takes no tap meant for the field or the "+"
/// (only its own pixels above the edge it sits on), is hidden from VoiceOver, makes no sound, and is gone when
/// Settings → Extras → Companions is off. Reduce Motion draws the still pose for the hour and the weather and runs
/// nothing; Reduce Effects and Low Power Mode keep the small gestures and drop the flourish.
struct CompanionPerch: View {
    enum Spot {
        /// The Mac sidebar's search field.
        case searchField
        /// The iPhone's and iPad's floating "+".
        case addButton

        var place: CompanionPlace {
            switch self {
            case .searchField: .field
            case .addButton: .plus
            }
        }

        /// From the host's trailing edge to the right edge of the companion's resting pose, in points (whole
        /// points, so every pixel stays crisp). Its seat row lies on the host's top edge.
        var trailing: CGFloat {
            switch self {
            case .searchField: 14
            case .addButton: 8
            }
        }
    }

    let spot: Spot
    @AppStorage(Preferences.companions, store: AppGroup.defaults) private var enabled = true
    @HITEffectsSetting private var effects

    init(_ spot: Spot) {
        self.spot = spot
    }

    /// The overlay alignment that goes with `spot`.
    static func alignment(_ spot: Spot) -> Alignment { .topTrailing }

    var body: some View {
        if enabled {
            let character = CompanionCast.current
            CompanionLife(character: character, place: spot.place, still: effects.reduceMotion,
                          calm: effects.reduceEffects)
                .offset(Self.offset(character, spot: spot))
                .accessibilityHidden(true)
                // A theme change is a different companion: the old one leaves the screen, the new one arrives.
                .id(character.id)
        }
    }

    /// The sprite's offset from the host's top-trailing corner: its resting pose's rightmost pixel `spot.trailing`
    /// in from the edge, its seat row on the top edge.
    static func offset(_ character: CompanionCharacter, spot: Spot) -> CGSize {
        let p = CompanionCharacter.pointsPerPixel
        let rest = character.posture(spot.place).awake.rest
        let clearColumns = character.width - 1 - character.rightmostColumn(rest)
        let x: CGFloat = CGFloat(clearColumns) * p - spot.trailing
        let y: CGFloat = -CGFloat(character.seatRow) * p
        return CGSize(width: x, height: y)
    }
}

/// A companion on screen: registers with the director while it shows, and draws its pose on the clock's
/// timeline while an act plays (only while the app is active and motion is allowed); a still picture otherwise.
private struct CompanionLife: View {
    let character: CompanionCharacter
    let place: CompanionPlace
    let still: Bool
    let calm: Bool

    var body: some View {
        let director = CompanionDirector.shared
        let clock = director.clock(for: character)
        let stage = director.stages[character.id]
            ?? CompanionStage(since: .now, place: place, look: director.look(at: .now))
        let rest = clock.restPose(at: .now, stage: stage)
        Group {
            if !still, director.isAppActive, stage.act != nil {
                TimelineView(CompanionTimeline(clock: clock, stage: stage)) { context in
                    CompanionSprite(character: character, pose: clock.pose(at: context.date, stage: stage))
                }
            } else {
                CompanionSprite(character: character, pose: rest)
            }
        }
        .contentShape(TapArea(runs: character.drawn[rest.frame], width: character.width, seatRow: character.seatRow,
                              mirrored: rest.mirrored))
        .onTapGesture { director.tap(character.id) }
        .onAppear { director.appear(character.id, place: place, still: still, calm: calm) }
        .onDisappear { director.disappear(character.id) }
        .onChange(of: still) { _, new in director.setMotion(character.id, still: new, calm: calm) }
        .onChange(of: calm) { _, new in director.setMotion(character.id, still: still, calm: new) }
    }
}

/// The companion's own pixels above the edge it sits on (a pixel's slack around them): a tap below the edge is the
/// field's or the "+"'s.
private struct TapArea: Shape {
    let runs: [CompanionCharacter.Run]
    let width: Int
    let seatRow: Int
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        CompanionCharacter.tapShape(runs: runs, width: width, mirrored: mirrored, belowRow: seatRow)
    }
}
