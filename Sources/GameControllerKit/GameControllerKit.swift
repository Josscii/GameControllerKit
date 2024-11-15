//
//  GameControllerKit.swift
//  GameControllerKit
//
//  Created by Wesley de Groot on 2024-08-19.
//  https://wesleydegroot.nl
//
//  https://github.com/0xWDG/GameControllerKit
//  MIT License
//

import Foundation
import GameController
import CoreHaptics
import OSLog

/// Game Controller Kit
///
/// GameControllerKit is a Swift package that makes it easy to work with
/// game controllers on iOS, macOS, and tvOS. It provides a simple API to
/// connect to game controllers, read input from them, and control their
/// lights and haptics.
public class GameControllerKit: ObservableObject {
    /// Event Handler
    public typealias GCKEventHandler = (_ action: GCKAction, _ pressed: Bool, _ controller: GCKController) -> Void

    /// The type of game controller that is currently connected, if any.
    /// This property is nil if no controller is connected.
    @Published
    public var controllerType: GCKControllerType? = .none

    /// The game controller that is currently connected, if any. (this is always the first controller)
    @Published
    public var controller: GCKController?

    /// The game controllers that are currently connected, if any.
    @Published
    public var controllers: [GCKController] = []

    /// The current state of the left thumbstick.
    @Published
    public var leftThumbstick: GCKMovePosition = .centered

    /// The current state of the right thumbstick.
    @Published
    public var rightThumbstick: GCKMovePosition = .centered

    /// The last action done by the controller
    @Published
    public var lastAction: GCKAction = .none

    /// Action handler for the actions performed by the user on the controller
    private var eventHandler: GCKEventHandler?

    /// Game Controller Kit logger.
    private var logger = Logger(
        subsystem: "nl.wesleydegroot.GameControllerKit",
        category: "GameControllerKit"
    )

    /// Indicates whether a game controller is currently connected.
    public var isConnected: Bool = false

    /// Initializes a new GameControllerKit instance.
    /// It sets up notification observers for when game controllers connect or disconnect.
    ///
    /// - Parameter logger: Custom ``Logger`` instance. (optional)
    public init(logger: Logger? = nil) {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main,
            using: controllerDidConnect
        )

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main,
            using: controllerDidDisconnect
        )

        self.eventHandler = { [weak self] button, pressed, controller in
            let message = "Controller #\(String(describing: controller.playerIndex.rawValue)), " +
            "Button \(String(describing: button)) \(button.position.arrowRepresentation) " +
            "is \(pressed ? "Pressed" : "Unpressed")"

            self?.logger.info("\(String(describing: message))")
        }

        if let logger = logger {
            self.logger = logger
        }
    }

    /// Set color of the controllers light
    ///
    /// Use the light settings to signal the user or to create a more immersive experience.
    /// If the controller doesn’t provide light settings, this property is nil.
    ///
    /// - Parameter color: Color
    public func set(color: GCColor) {
        controller?.light?.color = color
    }

    /// Set the event handler
    ///
    /// This function allows you to setup a custom event handler, 
    /// which you need to receive inputs from the controller.
    ///
    /// - Parameter handler: event handler
    public func set(handler: @escaping GCKEventHandler) {
        self.eventHandler = handler
    }

    /// Plays random colors on your controller (if supported)
    /// This is currently only supported on a DualSense and DualShock controller (Playstation)
    public func randomColors() {
        for counter in 0...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(counter)/0.99)) {
                self.set(color: .GCKRandom)
            }
        }
    }

    /// Play haptics
    ///
    /// This plays haptics (vibrations) on the gamecontroller.
    ///
    /// - Parameter url: Haptics file
    public func playHaptics(url: URL) {
        guard let haptics = self.controller?.haptics?.createEngine(withLocality: .default) else {
            logger.fault("Couldn't initialize haptics")
            return
        }

        do {
            // Start the engine in case it's idle.
            try haptics.start()

            // Tell the engine to play a pattern.
            try haptics.playPattern(from: url)
        } catch {
            // Process engine startup errors.
            logger.fault("An error occured playing haptics: \(error).")
        }
    }

    // MARK: - Connect/Disconnect functions
    /// Controller did connect
    ///
    /// This function handles the connection of a controller.
    /// If it is the first controller it will set to the primary controller
    @objc private func controllerDidConnect(_ notification: Notification) {
        controllers = GCController.controllers()

        guard !controllers.isEmpty else {
            logger.fault("Failed to get the controller")
            return
        }

        for (index, currentController) in controllers.enumerated() {
            currentController.playerIndex = GCControllerPlayerIndex(rawValue: index) ?? .indexUnset

            let currentControllerType: GCKControllerType = switch currentController.physicalInputProfile {
            case is GCDualSenseGamepad:
                    .dualSense

            case is GCDualShockGamepad:
                    .dualShock

            case is GCXboxGamepad:
                    .xbox

            case is GCMicroGamepad:
                    .siriRemote
            default:
                    .generic
            }

            let contr = String(describing: currentControllerType)
            logger.info(
                "Did connect controller \(currentController.productCategory) recognized as \(contr)."
            )

            if !isConnected && currentControllerType != .siriRemote {
                isConnected = true
                controller = currentController
                controllerType = currentControllerType

                logger.info(
                    "Did set controller \(currentController.productCategory) as main (first) controller."
                )
            }

            setupController(controller: currentController)
        }
    }

    /// Controller did disconnect
    ///
    /// This function handles the disconnection of a controller.
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        controllers = GCController.controllers()

        if controller == notification.object as? GCController? {
            logger.debug("The primary controller is disconnected")
            isConnected = false
            self.controllerType = nil

            if !controllers.isEmpty {
                logger.debug("Setup a new primary controller")
                controllerDidConnect(notification)
            }

            return
        }

        logger.debug("A controller is disconnected")
    }

    // MARK: - Setup controller

    /// Set up controller
    ///
    /// This function sets up the controller, 
    /// it looks which type it is and then map the elements to the corresponding responders.
    ///
    /// - Parameter controller: Controller
    func setupController(controller: GCController) {
        // swiftlint:disable:previous function_body_length
        var buttons: [(GCControllerButtonInput?, GCKAction)] = []

        if let gamepad = controller.extendedGamepad {
            buttons.append(contentsOf: [
                (gamepad.buttonA, .buttonA),
                (gamepad.buttonB, .buttonB),
                (gamepad.buttonX, .buttonX),
                (gamepad.buttonY, .buttonY),
                (gamepad.leftShoulder, .leftShoulder),
                (gamepad.rightShoulder, .rightShoulder),
                (gamepad.leftTrigger, .leftTrigger),
                (gamepad.rightTrigger, .rightTrigger),
                (gamepad.buttonMenu, .buttonMenu),
                (gamepad.buttonOptions, .buttonOptions),
                (gamepad.buttonHome, .buttonHome),
                (gamepad.leftThumbstickButton, .leftThumbstickButton),
                (gamepad.rightThumbstickButton, .rightThumbstickButton),
                (gamepad.dpad.up, .dpadUp),
                (gamepad.dpad.down, .dpadDown),
                (gamepad.dpad.left, .dpadLeft),
                (gamepad.dpad.right, .dpadRight),
                (gamepad.leftThumbstick.up, .dpadUp),
                (gamepad.leftThumbstick.down, .dpadDown),
                (gamepad.leftThumbstick.left, .dpadLeft),
                (gamepad.leftThumbstick.right, .dpadRight),
                (gamepad.rightThumbstick.up, .dpadUp),
                (gamepad.rightThumbstick.down, .dpadDown),
                (gamepad.rightThumbstick.left, .dpadLeft),
                (gamepad.rightThumbstick.right, .dpadRight)
            ])

            if let playstationGamepad = controller.physicalInputProfile as? GCDualSenseGamepad {
                buttons.append(
                    contentsOf: [
                        (playstationGamepad.touchpadButton, .touchpadButton),
                        (playstationGamepad.touchpadPrimary.up, .touchpadPrimaryUp),
                        (playstationGamepad.touchpadPrimary.right, .touchpadPrimaryRight),
                        (playstationGamepad.touchpadPrimary.left, .touchpadPrimaryLeft),
                        (playstationGamepad.touchpadPrimary.down, .touchpadPrimaryDown),
                        (playstationGamepad.touchpadSecondary.up, .touchpadSecondaryUp),
                        (playstationGamepad.touchpadSecondary.right, .touchpadSecondaryRight),
                        (playstationGamepad.touchpadSecondary.down, .touchpadSecondaryDown),
                        (playstationGamepad.touchpadSecondary.left, .touchpadSecondaryLeft)
                    ]
                )
            }

            if let playstationGamepad = controller.physicalInputProfile as? GCDualShockGamepad {
                buttons.append(
                    contentsOf: [
                        (playstationGamepad.touchpadButton, .touchpadButton),
                        (playstationGamepad.touchpadPrimary.up, .touchpadPrimaryUp),
                        (playstationGamepad.touchpadPrimary.right, .touchpadPrimaryRight),
                        (playstationGamepad.touchpadPrimary.left, .touchpadPrimaryLeft),
                        (playstationGamepad.touchpadPrimary.down, .touchpadPrimaryDown),
                        (playstationGamepad.touchpadSecondary.up, .touchpadSecondaryUp),
                        (playstationGamepad.touchpadSecondary.right, .touchpadSecondaryRight),
                        (playstationGamepad.touchpadSecondary.down, .touchpadSecondaryDown),
                        (playstationGamepad.touchpadSecondary.left, .touchpadSecondaryLeft)
                    ]
                )
            }

            if let xboxGamepad = controller.physicalInputProfile as? GCXboxGamepad {
                buttons.append(
                    contentsOf: [
                        (xboxGamepad.buttonShare, .shareButton),
                        (xboxGamepad.paddleButton1, .paddleButton1),
                        (xboxGamepad.paddleButton2, .paddleButton2),
                        (xboxGamepad.paddleButton3, .paddleButton3),
                        (xboxGamepad.paddleButton4, .paddleButton4)
                    ]
                )
            }

            for (button, name) in buttons {
                button?.valueChangedHandler = { [weak self] (_, _, pressed) in
                    self?.lastAction = name
                    self?.eventHandler?(name, pressed, controller)
                }
            }

            gamepad.leftThumbstick.valueChangedHandler = { (_, xPos, yPos) in
                let action: GCKAction = .leftThumbstick(x: xPos, y: yPos)
                self.lastAction = action
                self.leftThumbstick = action.position
                self.eventHandler?(action, false, controller)
            }

            gamepad.rightThumbstick.valueChangedHandler = { (_, xPos, yPos) in
                let action: GCKAction = .rightThumbstick(x: xPos, y: yPos)
                self.lastAction = action
                self.rightThumbstick = action.position
                self.eventHandler?(action, false, controller)
            }
        }
    }
}

extension GCColor {
    /// Random color
    ///
    /// - Returns: A random color.
    public static var GCKRandom: GCColor {
        return GCColor(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
}
