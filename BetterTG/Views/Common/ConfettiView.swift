// ConfettiView.swift

import UIKit

/// Telegram's ConfettiView (ConfettiEffect): 70 particles fall from above the screen and 80 burst in from both
/// lower corners, slow down for a moment at the top of their arc and fall away; the view removes itself once every
/// particle has left the screen. The chat plays it for a right quiz answer and a successful die roll.
final class ConfettiView: UIView {
    private struct Vector {
        var x: Float
        var y: Float
    }

    private final class Particle: CALayer {
        let mass: Float
        var velocity: Vector
        let angularVelocity: Float
        var rotationAngle: Float = 0
        let type: Int

        init(
            image: CGImage,
            size: CGSize,
            position: CGPoint,
            mass: Float,
            velocity: Vector,
            angularVelocity: Float,
            type: Int,
        ) {
            self.mass = mass
            self.velocity = velocity
            self.angularVelocity = angularVelocity
            self.type = type
            super.init()
            contents = image
            bounds = CGRect(origin: .zero, size: size)
            self.position = position
        }

        override init(layer: Any) {
            let particle = layer as? Particle
            self.mass = particle?.mass ?? 0
            self.velocity = particle?.velocity ?? Vector(x: 0, y: 0)
            self.angularVelocity = particle?.angularVelocity ?? 0
            self.type = particle?.type ?? 0
            super.init(layer: layer)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func action(forKey _: String) -> CAAction? {
            nil
        }
    }

    private static let colors: [UIColor] = [
        UIColor(red: 0x56 / 255, green: 0xCE / 255, blue: 0x6B / 255, alpha: 1),
        UIColor(red: 0xCD / 255, green: 0x89 / 255, blue: 0xD0 / 255, alpha: 1),
        UIColor(red: 0x1E / 255, green: 0x9A / 255, blue: 0xFF / 255, alpha: 1),
        UIColor(red: 0xFF / 255, green: 0x87 / 255, blue: 0x24 / 255, alpha: 1),
    ]
    private static let typeDelays: [Float] = [0, 0.01, 0.08]

    private var particles = [Particle]()
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var localTime: Float = 0
    private var slowdownStarts: [Float?] = [nil, nil, nil]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let images = Self.images()
        let imageCount = images.count

        let sizeVariation: ClosedRange<Float> = 0.8...1.6
        let angularVelocityRange: ClosedRange<Float> = 1...6
        // Particles falling from above the screen.
        for index in 0..<70 {
            let (image, size) = images[index % imageCount]
            let scale = CGFloat(Float.random(in: sizeVariation))
            addParticle(Particle(
                image: image,
                size: CGSize(width: size.width * scale, height: size.height * scale),
                position: CGPoint(
                    x: CGFloat.random(in: 0...max(1, frame.width)),
                    y: CGFloat.random(in: -max(1, frame.height)...0),
                ),
                mass: Float.random(in: 40...50),
                velocity: Vector(x: 0, y: Float.random(in: 3...5)),
                angularVelocity: Float.random(in: angularVelocityRange),
                type: 0,
            ))
        }

        // Bursts from both lower corners.
        let sideOriginY = Float(frame.height * 9 / 10)
        let velocityScaling = 2400 * Float(frame.height) / 896
        let baseAngle = Float.pi / 2 + atanf(sideOriginY / Float(max(1, frame.width * 0.8)))
        let amplitudeDiameter: CGFloat = 230
        for side in 0..<2 {
            let sign: Float = side == 0 ? 1 : -1
            let baseX = side == 0 ? -amplitudeDiameter / 2 : frame.width + amplitudeDiameter / 2
            for index in 0..<40 {
                let originAngle = Float.random(in: 0..<(Float.pi * 2))
                let originAmplitude = Float.random(in: 0..<Float(amplitudeDiameter / 2))
                let velocityValue = Float.random(in: 1.1..<1.3) * velocityScaling
                let velocityAngle = Float.random(in: (baseAngle - 0.09)..<(baseAngle + 0.09))
                let (image, size) = images[index % imageCount]
                let scale = CGFloat(Float.random(in: sizeVariation))
                addParticle(Particle(
                    image: image,
                    size: CGSize(width: size.width * scale, height: size.height * scale),
                    position: CGPoint(
                        x: baseX + CGFloat(cosf(originAngle) * originAmplitude),
                        y: CGFloat(sideOriginY + sinf(originAngle) * originAmplitude),
                    ),
                    mass: Float.random(in: 110..<120),
                    velocity: Vector(
                        x: sign * velocityValue * sinf(velocityAngle),
                        y: velocityValue * cosf(velocityAngle),
                    ),
                    angularVelocity: Float.random(in: angularVelocityRange),
                    type: index % 3,
                ))
            }
        }

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func removeFromSuperview() {
        displayLink?.invalidate()
        displayLink = nil
        super.removeFromSuperview()
    }

    /// Dots and rounded strips in Telegram's four colors.
    private static func images() -> [(CGImage, CGSize)] {
        var images = [(CGImage, CGSize)]()
        let dotSize = CGSize(width: 8, height: 8)
        let stripSize = CGSize(width: 2, height: 6)
        for color in colors {
            let dot = UIGraphicsImageRenderer(size: dotSize).image { context in
                color.setFill()
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: dotSize))
            }
            if let image = dot.cgImage { images.append((image, dotSize)) }
        }
        for color in colors {
            let strip = UIGraphicsImageRenderer(size: stripSize).image { _ in
                color.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: stripSize), cornerRadius: stripSize.width / 2)
                    .fill()
            }
            if let image = strip.cgImage { images.append((image, stripSize)) }
        }
        return images
    }

    private func addParticle(_ particle: Particle) {
        particles.append(particle)
        layer.addSublayer(particle)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        defer { previousTimestamp = timestamp }
        guard let previousTimestamp else { return }
        step(dt: Float(min(0.05, timestamp - previousTimestamp)))
    }

    /// ConfettiView.step: each kind slows for 0.7 s once its particles start falling, then gravity and a little
    /// turbulence take them down.
    private func step(dt: Float) {
        slowdownStarts[0] = 0.33
        var steps = [Float]()
        for type in 0..<3 {
            let currentTime = localTime - Self.typeDelays[type]
            if currentTime < 0 {
                steps.append(0)
            } else if let start = slowdownStarts[type], currentTime >= start, currentTime <= start + 0.7 {
                let elapsed = currentTime - start
                let raw: Float =
                    if elapsed < 0.05 {
                        elapsed / 0.05
                    } else if elapsed >= 0.5 {
                        1 - (elapsed - 0.5) / 0.2
                    } else {
                        1
                    }
                let transition = raw * raw
                steps.append(dt * (0.8 * transition + (1 - transition)))
            } else {
                steps.append(dt)
            }
        }
        localTime += dt

        let gravity: Float = 9.8
        var turbulence = [Float]()
        for _ in 0..<20 {
            turbulence.append(Float.random(in: -16..<16) * 60)
        }
        var fallingTypes = [false, false, false]
        var onScreen = false
        let maxY = bounds.height + 30
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, particle) in particles.enumerated() {
            let localDt = steps[particle.type]
            guard localDt > 0 else { continue }
            var position = particle.position
            position.x += CGFloat(particle.velocity.x * localDt)
            position.y += CGFloat(particle.velocity.y * localDt)
            particle.position = position
            particle.rotationAngle += particle.angularVelocity * localDt
            particle.transform = CATransform3DMakeRotation(CGFloat(particle.rotationAngle), 0, 0, 1)

            var velocity = particle.velocity
            velocity.y += gravity * particle.mass * localDt
            if velocity.y < 0 {
                velocity.x *= 0.93
                velocity.y *= 0.93
            } else {
                velocity.x += turbulence[index % turbulence.count] * localDt
                fallingTypes[particle.type] = true
            }
            particle.velocity = velocity
            if position.y < maxY { onScreen = true }
        }
        for type in 0..<3 where fallingTypes[type] && slowdownStarts[type] == nil {
            slowdownStarts[type] = max(0, localTime - Self.typeDelays[type])
        }
        CATransaction.commit()
        if !onScreen { removeFromSuperview() }
    }
}
