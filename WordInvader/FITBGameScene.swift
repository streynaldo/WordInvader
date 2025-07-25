//
//  GameScene.swift
//  WordInvader
//
//  Created by Stefanus Reynaldo on 09/07/25.
//

import SpriteKit
import AVFoundation

extension Notification.Name {
    static let didFITBGameOver = Notification.Name("didFITBGameOver")
}

class FITBGameScene: SKScene, SKPhysicsContactDelegate {
    
    var gameKitManager: GameKitManager?
    
    var spaceship: SKSpriteNode!
    var previousTouchPosition: CGPoint?
    
    var wordDataManager : WordDataManager! = nil
    let gameManager = GameManager.shared
    
    var currentTask: WordTask!
    var currentGameSession: GameSession!
    var score : Int = 0
    var streak: Int = 0
    
    var isResetting = false
    
    let shootSound = SKAction.playSoundFileNamed("shoot.mp3", waitForCompletion: false)
    let explosionSound = SKAction.playSoundFileNamed("explosion.mp3", waitForCompletion: false)
    let wrongSound = SKAction.playSoundFileNamed("wrong.mp3", waitForCompletion: false)
    
    let spaceshipIdle = SKTexture(imageNamed: "spaceship_idle")
    let spaceshipLeft = SKTexture(imageNamed: "spaceship_left")
    let spaceshipRight = SKTexture(imageNamed: "spaceship_right")
    
    var onNewHighScore: (() -> Void)?
    private var personalHighScore: Int = (UserDefaults.standard.integer(forKey: "personalHighScore_FITB") != 0) ? UserDefaults.standard.integer(forKey: "personalHighScore_FITB") : 0
    
    var obstacleSpeed : CGFloat = 10
    
    var backgroundMusic: SKAudioNode?
    
    var isCountingDown = false
    
    private var windAnimation: SKAction?
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(named: "background_color") ?? .black
        if let musicURL = Bundle.main.url(
            forResource: "bgm",
            withExtension: "mp3"
        ) {
            backgroundMusic = SKAudioNode(url: musicURL)
            backgroundMusic?.autoplayLooped = true
            if !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
                addChild(backgroundMusic!)
                        }
//            addChild(backgroundMusic!)
        }
        
        currentGameSession = GameSession()
        
        let background = SKSpriteNode(imageNamed: "background")
        background.position = CGPoint(x: size.width/2, y: size.height/2)
        background.zPosition = -1  // Pastikan di belakang semua node
        background.size = size     // Atur agar full screen
        
        addChild(background)
        setupParallaxBackground()
        setupFallingWindEffect()
        setupSpaceship()
        
        // 🚨 Ini WAJIB 🚨
        physicsWorld.contactDelegate = self
        
        let floorNode = SKNode()
        floorNode.position = CGPoint(x: size.width / 2, y: 0) // dasar screen
        floorNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 10))
        floorNode.physicsBody?.isDynamic = false
        floorNode.physicsBody?.categoryBitMask = 0x1 << 3 // FLOOR = kategori 3
        floorNode.physicsBody?.contactTestBitMask = 0x1 << 1 // obstacle = kategori 1
        floorNode.physicsBody?.collisionBitMask = 0
        addChild(floorNode)
        
        spawnObstacleRow()
    }
    
    func configure(with wordDataManager: WordDataManager) {
        self.wordDataManager = wordDataManager
    }
    
    func didBegin(_ contact: SKPhysicsContact) {
        // Jangan proses kalau sedang reset
        if isResetting { return }
        
        var letterNode: SKNode?
        var bulletNode: SKNode?
        var spaceshipHit = false
        var floorHit = false
        
        if contact.bodyA.categoryBitMask == 0x1 << 3 || contact.bodyB.categoryBitMask == 0x1 << 3 {
            floorHit = true
        }
        
        if floorHit {
            if contact.bodyA.node?.name?.hasPrefix("letter_") == true {
                letterNode = contact.bodyA.node
            } else if contact.bodyB.node?.name?.hasPrefix("letter_") == true {
                letterNode = contact.bodyB.node
            }
            
            if let hit = letterNode {
                hit.removeFromParent()
            }
            
            // Kalo node kelewat minus hp
            if let task = currentTask, !task.isComplete {
                gameManager.score -= 25
                score -= 25
                streak = 0
                if gameManager.score <= 0 {
                    gameManager.score = 0
                    score = 0
                }
            }
            
            currentTask = nil
            trySpawnIfClear()
            return
        }
        
        if contact.bodyA.node == spaceship || contact.bodyB.node == spaceship {
            spaceshipHit = true
        }
        if contact.bodyA.node?.name?
            .hasPrefix("letter_") == true { letterNode = contact.bodyA.node }
        else if contact.bodyB.node?.name?.hasPrefix("letter_") == true {
            letterNode = contact.bodyB.node
        }
        
        if spaceshipHit, let hitObstacle = letterNode {
            run(explosionSound)
            HapticsManager.shared.trigger(.error)
            createExplosion(at: hitObstacle.position)
            
            showBrokenHeartEffect(at: hitObstacle.position)
            
            hitObstacle.removeFromParent()
            gameManager.health -= 10
            if gameManager.health <= 0 { resetGame(isGameOver: true) }
            return
        }
        
        if contact.bodyA.node?.name == "bullet" { bulletNode = contact.bodyA.node }
        else if contact.bodyB.node?.name == "bullet" { bulletNode = contact.bodyB.node }
        
        if letterNode == nil {
            if contact.bodyA.node?.name?.hasPrefix("letter_") == true { letterNode = contact.bodyA.node }
            else if contact.bodyB.node?.name?.hasPrefix("letter_") == true { letterNode = contact.bodyB.node }
        }
        
        guard let hit = letterNode, let bullet = bulletNode, let name = hit.name, hit.parent != nil else { return }
        
        bullet.removeFromParent()
        let letter = name.replacingOccurrences(of: "letter_", with: "").first!
        
        if let task = currentTask, task.remainingLetters.contains(letter) {
            task.fill(letter: letter)
            createExplosion(at: hit.position)
            run(explosionSound)
            HapticsManager.shared.impact(style: .medium)
            hit.removeFromParent()
            gameManager.currentTaskText = task.display
            
            if task.isComplete {
                gameManager.score += 50
                score += 50
                
                if let manager = gameKitManager {
                    gameManager.checkRealtimeAchievements(for: manager)
                }
                
                currentTask = nil
                gameManager.currentTaskText = "Good Job"
                run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.5),
                    SKAction.run { [weak self] in self?.trySpawnIfClear() }
                ]))
            }
        } else {
//            SALAH
            let shake = SKAction.sequence([
                .moveBy(x: 10, y: 0, duration: 0.05),
                .moveBy(x: -20, y: 0, duration: 0.1),
                .moveBy(x: 10, y: 0, duration: 0.05)
            ])
            hit.run(shake)
            showBrokenHeartEffect(at: hit.position)
            run(wrongSound)
            HapticsManager.shared.trigger(.error)
            gameManager.score -= 10
            score -= 10
            if gameManager.score <= 0 {
                gameManager.score = 0
                score = 0
            }
        }
        
        // Decoy tetap jalan kalau salah huruf
    }
    
    private func showBrokenHeartEffect(at position: CGPoint) {
        let brokenHeart = SKSpriteNode(imageNamed: "broken_heart")
        brokenHeart.position = position
        brokenHeart.size = CGSize(width: 60, height: 60)
        brokenHeart.zPosition = 15 // Paling depan
        brokenHeart.alpha = 0.0
        
        let fadeIn = SKAction.fadeIn(withDuration: 0.1)
        let wait = SKAction.wait(forDuration: 0.5)
        let moveUp = SKAction.moveBy(x: 0, y: 30, duration: 0.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        
        let group = SKAction.group([moveUp, fadeOut])
        let sequence = SKAction.sequence([fadeIn, wait, group, .removeFromParent()])
        
        brokenHeart.run(sequence)
        addChild(brokenHeart)
    }
    
    private func setupFallingWindEffect() {
        let createWindParticle = SKAction.run { [weak self] in
            self?.spawnWindParticle()
        }
        let wait = SKAction.wait(forDuration: 0.08, withRange: 0.1)
        
        let sequence = SKAction.sequence([createWindParticle, wait])
        let repeatForever = SKAction.repeatForever(sequence)
        
        run(repeatForever, withKey: "windSpawner")
    }
    
    private func spawnWindParticle() {
        let windImageNumber = Int.random(in: 1...4)
        let windNode = SKSpriteNode(imageNamed: "spaceship_wind_\(windImageNumber)")
        
        let randomX = CGFloat.random(in: 0...size.width)
        windNode.position = CGPoint(x: randomX, y: self.size.height + 100)
        
        windNode.size = CGSize(width: 3, height: 60)
        
        windNode.alpha = CGFloat.random(in: 0.2...0.5)
        windNode.zRotation = 0
        windNode.zPosition = 5
        
        let destinationY = -100.0
        let randomDuration = TimeInterval.random(in: 2.0...3.0)
        let moveAction = SKAction.moveTo(y: destinationY, duration: randomDuration)
        
        let removeAction = SKAction.removeFromParent()
        windNode.run(SKAction.sequence([moveAction, removeAction]))
        
        addChild(windNode)
    }
    
    private func setupSpaceship() {
        spaceship = SKSpriteNode(imageNamed: "spaceship_idle")
        spaceship.size = CGSize(width: 60, height: 70)
        spaceship.position = CGPoint(x: size.width / 2, y: 100)
        spaceship.name = "player"
        spaceship.zPosition = 10
        addChild(spaceship)
        spaceship.physicsBody = SKPhysicsBody(rectangleOf: spaceship.size)
        spaceship.physicsBody?.isDynamic = false
        spaceship.physicsBody?.categoryBitMask = 0x1 << 2
        spaceship.physicsBody?.contactTestBitMask = 0x1 << 1
        spaceship.physicsBody?.collisionBitMask = 0
    }
    
    
    private func setupParallaxBackground() {
        for i in 0...1 {
            let strip = createCompleteParallaxStrip()
            strip.position = CGPoint(x: 0, y: self.size.height * CGFloat(i))
            strip.name = "parallax_strip"
            addChild(strip)
        }
    }
    
    private func createCompleteParallaxStrip() -> SKNode {
        let container = SKNode()
        var occupiedFrames = [CGRect]()
        
        placeAssets(
            on: container,
            textureNames: ["galaxy"],
            count: 2,
            zPosition: -9,
            occupiedFrames: &occupiedFrames
        )
        placeAssets(
            on: container,
            textureNames: ["cloud_1", "cloud_2", "cloud_3"],
            count: 4,
            zPosition: -8,
            occupiedFrames: &occupiedFrames
        )
        placeAssets(
            on: container,
            textureNames: ["cloud_4", "cloud_5", "cloud_6"],
            count: 4,
            zPosition: -8,
            occupiedFrames: &occupiedFrames
        )
        placeStars(on: container, count: 50, zPosition: -7)
        
        return container
    }
    
    private func placeStars(
        on container: SKNode,
        count: Int,
        zPosition: CGFloat
    ) {
        for _ in 0..<count {
            let starNumber = Int.random(in: 1...5)
            let star = SKSpriteNode(imageNamed: "star_\(starNumber)")
            star.position = CGPoint(
                x: .random(in: 0...self.size.width),
                y: .random(in: 0...self.size.height)
            )
            star.setScale(.random(in: 0.05...0.2))
            star.alpha = .random(in: 0.4...1.0)
            star.zPosition = zPosition
            
            let fadeDuration = TimeInterval.random(in: 0.4...0.8)
            let waitDuration = TimeInterval.random(in: 1.0...1.5)
            
            let fadeOut = SKAction.fadeAlpha(to: .random(in: 0.1...0.4), duration: fadeDuration)
            let waitWhileDim = SKAction.wait(forDuration: waitDuration / 2)
            
            let fadeIn = SKAction.fadeAlpha(to: .random(in: 0.6...0.8), duration: fadeDuration)
            let waitWhileBright = SKAction.wait(forDuration: waitDuration)
            
            let sequence = SKAction.sequence([fadeOut, waitWhileDim, fadeIn, waitWhileBright])
            
            let twinkle = SKAction.repeatForever(sequence)
            
            star.run(twinkle)
            
            container.addChild(star)
        }
    }
    
    private func placeAssets(
        on container: SKNode,
        textureNames: [String],
        count: Int,
        zPosition: CGFloat,
        occupiedFrames: inout [CGRect]
    ) {
        for _ in 0..<count {
            let textureName = textureNames.randomElement()!
            let node = SKSpriteNode(imageNamed: textureName)
            
            let aspectRatio = node.texture!.size().height / node.texture!.size().width
            let nodeWidth = self.size.width * CGFloat.random(in: 0.25...0.50)
            node.size = CGSize(
                width: nodeWidth,
                height: nodeWidth * aspectRatio
            )
            
            var attempts = 0
            var positionIsSafe = false
            
            while !positionIsSafe && attempts < 20 {
                let xPos = CGFloat.random(in: 0...self.size.width)
                let yPos = CGFloat.random(in: 0...self.size.height)
                node.position = CGPoint(x: xPos, y: yPos)
                
                let nodeFrameWithPadding = node.frame.insetBy(dx: -20, dy: -20)
                positionIsSafe = !occupiedFrames
                    .contains { $0.intersects(nodeFrameWithPadding) }
                attempts += 1
            }
            
            if positionIsSafe {
                occupiedFrames.append(node.frame)
                node.zPosition = zPosition
                container.addChild(node)
            }
        }
    }
    
    private func moveBackgroundStrip(speed: CGFloat) {
        self.enumerateChildNodes(withName: "parallax_strip") { (node, stop) in
            node.position.y -= speed
            if node.position.y < -self.size.height {
                node.position.y += self.size.height * 2
            }
        }
    }
    
    func removeRemainingLettersWithExplosions() {
        let letterNodes = children.filter { node in
            node.name?.hasPrefix("letter_") == true
        }
        
        for (index, letterNode) in letterNodes.enumerated() {
            // Stagger the explosions slightly for visual effect
            let delay = Double(index) * 0.1
            
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self = self else { return }
                    self.createExplosion(at: letterNode.position)
                    self.run(self.explosionSound)
                    letterNode.removeFromParent()
                }
            ]))
        }
    }
    
    
    func trySpawnIfClear() {
        if isResetting { return } // Stop kalau reset sedang jalan
        
        let stillHasObstacles = children.contains { node in
            node.name?.hasPrefix("letter_") == true
        }
        
        if stillHasObstacles {
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.5),
                SKAction.run { [weak self] in
                    self?.trySpawnIfClear()
                }
            ]))
        } else {
            spawnObstacleRow()
        }
    }
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gameManager.isGameOver && !isPaused && !isCountingDown else { return }
        if let touch = touches.first {
            previousTouchPosition = touch.location(in: self)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gameManager.isGameOver && !isPaused && !isCountingDown else { return }
        guard let touch = touches.first,
              let previousPosition = previousTouchPosition else { return }
        
        let currentPosition = touch.location(in: self)
        let deltaX = currentPosition.x - previousPosition.x
        
        spaceship.position.x += deltaX
        
        if deltaX > 0 {
            spaceship.texture = spaceshipRight
        } else if deltaX < 0 {
            spaceship.texture = spaceshipLeft
        } else {
            spaceship.texture = spaceshipIdle
        }
        
        spaceship.position.x = max(spaceship.size.width / 2, spaceship.position.x)
        spaceship.position.x = min(size.width - spaceship.size.width / 2, spaceship.position.x)
        
        previousTouchPosition = currentPosition
    }

    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !gameManager.isGameOver && !isPaused && !isCountingDown else { return }
        previousTouchPosition = nil
        spaceship.texture = spaceshipIdle
        fireBullet()
        run(shootSound)
        HapticsManager.shared.impact(style: .light)
    }
    
    
    func spawnObstacleRow() {
        // Generate new word task using SwiftData
        if currentTask == nil || currentTask.isComplete {
            guard let word = wordDataManager.getRandomWord() else {
                // Reset word usage if no words available
                wordDataManager.resetWordUsage()
                guard let resetWord = wordDataManager.getRandomWord() else {
                    print("No words found even after reset")
                    return
                }
                createNewTask(with: resetWord)
                return
            }
            
            createNewTask(with: word)
        }
        
        // 🚫 Batasi obstacles target max 4 huruf (biar decoy max 5 total)
        var obstacles = Array(currentTask.remainingLetters.prefix(4))
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        
        while obstacles.count < 5 {
            let random = letters.randomElement()!
            if !obstacles.contains(random) {
                obstacles.append(random)
            }
        }
        
        obstacles.shuffle()
        
        let totalObstacles = obstacles.count
        let spacing = size.width / CGFloat(totalObstacles + 1)
        let yStart = size.height + 40
        
        // Hitung pengurang dari score
        let speedUpFactor = Double(gameManager.score / 100) * 0.5
        
        // Hitung durasi final, clamp ke minimum misalnya 3 detik
        obstacleSpeed = max(4.5, obstacleSpeed - speedUpFactor)
        
        for (i, letter) in obstacles.enumerated() {
            let randNumber = Int.random(in: 1...3)
            
            // 🔡 Buat huruf retro
            let letterNode = SKLabelNode(text: String(letter))
            letterNode.fontSize = 32
            letterNode.fontColor = .green // atau .white
            letterNode.fontName = "Courier-Bold"
            letterNode.horizontalAlignmentMode = .center
            letterNode.verticalAlignmentMode = .center
            
            let boxNode = SKSpriteNode(imageNamed: "rock\(randNumber)")
            boxNode.size = CGSize(width: 50, height: 50)
            
            let obstacle = SKNode()
            obstacle.name = "letter_\(letter)"
            obstacle.addChild(boxNode)
            obstacle.addChild(letterNode)
            
            letterNode.position = .zero
            boxNode.position = .zero
            
            let xPos = spacing * CGFloat(i + 1)
            obstacle.position = CGPoint(x: xPos, y: yStart)
            
            addChild(obstacle)
            
            // ⚡️ Durasi gerak dipercepat agar Node nggak numpuk
            let moveDown = SKAction.moveBy(x: 0, y: -size.height - 80, duration: obstacleSpeed)
            
            let check = SKAction.run { [weak self] in
                guard let self = self else { return }
                if let task = self.currentTask, !task.isComplete, !self.isResetting {
                    print("⚠️ Belum selesai, RESET")
                    self.isResetting = true
                    self.resetGame()
                }
            }
            
            let remove = SKAction.removeFromParent()
            obstacle.run(SKAction.sequence([moveDown, check, remove]))
            setupObstaclePhysics(obstacle)
        }
        
        // 📝 Update overlay kata
        gameManager.currentTaskText = currentTask.display
        print("Overlay: \(currentTask.display)")
    }
    
    private func createNewTask(with word: Word) {
        let wordText = word.text.uppercased()
        let blanksCount = min(Int.random(in: 1...2), wordText.count)
        let blankIndexes = Array(0..<wordText.count).shuffled().prefix(blanksCount)
        currentTask = WordTask(word: word, blanks: Array(blankIndexes))
        
        print("New Word: \(currentTask.word.text), blanks at: \(currentTask.blankIndexes)")
    }
    
    
    func fireBullet() {
        let bullet = SKSpriteNode(imageNamed: "bullet")
        bullet.size = CGSize(width: 10, height: 10)
        bullet.position = CGPoint(x: spaceship.position.x, y: spaceship.position.y + spaceship.size.height / 2 + 10)
        bullet.name = "bullet"
        
        bullet.physicsBody = SKPhysicsBody(circleOfRadius: 5)
        bullet.physicsBody?.categoryBitMask = 0x1 << 0 // kategori peluru
        bullet.physicsBody?.contactTestBitMask = 0x1 << 1 // bisa kontak dengan obstacle
        bullet.physicsBody?.collisionBitMask = 0
        bullet.physicsBody?.velocity = CGVector(dx: 0, dy: 400)
        bullet.physicsBody?.affectedByGravity = false
        
        addChild(bullet)
    }
    
    func setupObstaclePhysics(_ obstacle: SKNode) {
        obstacle.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 50, height: 50))
        obstacle.physicsBody?.categoryBitMask = 0x1 << 1 // obstacle = kategori 1
        obstacle.physicsBody?.contactTestBitMask = (0x1 << 0) | (0x1 << 2) | (0x1 << 3) // bullet, spaceship, floor
        obstacle.physicsBody?.collisionBitMask = 0
        obstacle.physicsBody?.affectedByGravity = false
    }
    
    func createExplosion(at position: CGPoint) {
        if let explosion = SKEmitterNode(fileNamed: "Explosion.sks") {
            explosion.position = position
            addChild(explosion)
            
            // Hapus node setelah efek selesai
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.5),
                SKAction.run { explosion.removeFromParent() }
            ]))
        }
    }
    func startNewGame() {
        // Clear obstacles
        for child in children {
            if child.name?.hasPrefix("letter_") == true {
                child.removeAllActions()
                child.removeFromParent()
            }
        }
        
        playBGM()
        obstacleSpeed = 8
        gameManager.score = 0
        score = 0
        gameManager.health = 5
        gameManager.isGameOver = false
        isResetting = false
        
        // Create new game session
        currentGameSession = GameSession()
        currentTask = nil
        spawnObstacleRow()
    }
    
    func resetGame(isGameOver: Bool = false) {
        guard !isResetting else { return }
        isResetting = true
        
        if isGameOver {
            // Save game session to SwiftData
            currentGameSession.duration = Date().timeIntervalSince(currentGameSession.dateStarted)
            wordDataManager.saveGameSession(currentGameSession)
            
            gameManager.isGameOver = true
            gameManager.currentTaskText = "Game Over!"
            
            // Show stats
            let stats = wordDataManager.getGameStats()
            print("Game Stats - Total Games: \(stats.totalGames), Best Score: \(stats.bestScore), Average: \(stats.averageScore)")
        } else {
            gameManager.isGameOver = false
            gameManager.currentTaskText = ""
        }
        
        // Bersihkan obstacles
        for child in children {
            if child.name?.hasPrefix("letter_") == true {
                child.removeAllActions()
                child.removeFromParent()
            }
        }
        
        if isGameOver {
            NotificationCenter.default.post(name: .didFITBGameOver, object: self)
            run(SKAction.sequence([
                SKAction.wait(forDuration: 2.0),
                SKAction.run { [weak self] in
                    guard let self = self else { return }
                    stopBGM()
                    self.gameManager.health = 5
                    self.isResetting = false
                }
            ]))
        } else {
            // Reset for new game
            gameManager.score = 0
            score = 0
            gameManager.health = 5
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.5),
                SKAction.run { [weak self] in
                    self?.isResetting = false
                    self?.spawnObstacleRow()
                }
            ]))
        }
    }
    
    func stopBGM() {
        backgroundMusic?.run(SKAction.stop())
    }
    
    func playBGM() {
        backgroundMusic?.run(SKAction.play())
    }
    
    func checkAchievementsAndSubmitScore(for manager: GameKitManager, finalScore: Int) {
        manager.submitScore(finalScore, to: "fill_in_the_blank_leaderboard")
        
        if finalScore >= 100 {
            manager.reportAchievement(identifier: "100_score_fill_in_the_blank")
        }
        if finalScore >= 1000 {
            manager.reportAchievement(identifier: "1000_score_fill_in_the_blank")
        }
        
        if finalScore > self.personalHighScore {
            self.personalHighScore = finalScore
            manager.reportAchievement(identifier: "new_personal_record_fill_in_the_blank")
            onNewHighScore?()
            saveHighScoreToDevice()
            print("New personal high score: \(finalScore)")
        }
    }
    
    private func saveHighScoreToDevice() {
        UserDefaults.standard.set(self.personalHighScore, forKey: "personalHighScore_FITB")
    }
    
    func randomMotivation() -> String {
        let messages = [
            "Keep practicing and beat your high score!",
            "You got this, Captain!",
            "Never give up, pilot! Try again!",
            "Your spaceship needs you!",
            "One more try! Show them who's boss!"
        ]
        return messages.randomElement() ?? ""
    }
    
    // Add these methods to your FITBGameScene class
    
    func pauseGame() {
        // Jangan pause kalau sedang countdown
        if isCountingDown { return }
        
        isPaused = true
        // Pause all actions
        for child in children {
            child.isPaused = true
        }
        // Pause physics
        physicsWorld.speed = 0
        
        // Tambahkan pause overlay
        let pauseOverlay = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.5), size: size)
        pauseOverlay.position = CGPoint(x: size.width/2, y: size.height/2)
        pauseOverlay.zPosition = 999
        pauseOverlay.name = "pauseOverlay"
        addChild(pauseOverlay)
        
        let pauseLabel = SKLabelNode(text: "PAUSED")
        pauseLabel.fontSize = 40
        pauseLabel.fontColor = .white
        pauseLabel.fontName = "Courier-Bold"
        pauseLabel.horizontalAlignmentMode = .center
        pauseLabel.verticalAlignmentMode = .center
        pauseLabel.position = .zero
        pauseOverlay.addChild(pauseLabel)
    }
    
    func resumeGame() {
        startCountdown()
    }
    
    private func startCountdown() {
        removePauseOverlay()
        
        // Set countdown state
        isCountingDown = true
        
        // PENTING: Pause physics world juga selama countdown
        physicsWorld.speed = 0
        
        // Pause semua obstacle actions selama countdown
        for child in children {
            if child.name?.hasPrefix("letter_") == true {
                child.isPaused = true
            }
        }
        
        // Buat countdown overlay
        let countdownOverlay = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: size)
        countdownOverlay.position = CGPoint(x: size.width/2, y: size.height/2)
        countdownOverlay.zPosition = 1000
        countdownOverlay.name = "countdownOverlay"
        addChild(countdownOverlay)
        
        // Buat label countdown
        let countdownLabel = SKLabelNode(text: "3")
        countdownLabel.fontSize = 80
        countdownLabel.fontColor = .white
        countdownLabel.fontName = "Courier-Bold"
        countdownLabel.horizontalAlignmentMode = .center
        countdownLabel.verticalAlignmentMode = .center
        countdownLabel.position = .zero
        countdownLabel.name = "countdownLabel"
        countdownOverlay.addChild(countdownLabel)
        
        // Animasi countdown 3, 2, 1, GO!
        let countdown3 = SKAction.run {
            countdownLabel.text = "3"
            countdownLabel.setScale(0.5)
            countdownLabel.run(SKAction.scale(to: 1.0, duration: 0.3))
        }
        
        let countdown2 = SKAction.run {
            countdownLabel.text = "2"
            countdownLabel.setScale(0.5)
            countdownLabel.run(SKAction.scale(to: 1.0, duration: 0.3))
        }
        
        let countdown1 = SKAction.run {
            countdownLabel.text = "1"
            countdownLabel.setScale(0.5)
            countdownLabel.run(SKAction.scale(to: 1.0, duration: 0.3))
        }
        
        let countdownGo = SKAction.run {
            countdownLabel.text = "GO!"
            countdownLabel.fontColor = .green
            countdownLabel.setScale(0.5)
            countdownLabel.run(SKAction.scale(to: 1.2, duration: 0.3))
        }
        
        let actualResume = SKAction.run { [weak self] in
            self?.performActualResume()
        }
        
        let removeOverlay = SKAction.run {
            countdownOverlay.removeFromParent()
        }
        
        // Jalankan sequence countdown
        let countdownSequence = SKAction.sequence([
            countdown3,
            SKAction.wait(forDuration: 1.0),
            countdown2,
            SKAction.wait(forDuration: 1.0),
            countdown1,
            SKAction.wait(forDuration: 1.0),
            countdownGo,
            SKAction.wait(forDuration: 0.5),
            actualResume,
            removeOverlay
        ])
        
        run(countdownSequence)
    }
    
    private func performActualResume() {
        isCountingDown = false
        isPaused = false
        
        // Resume all actions including obstacles
        for child in children {
            child.isPaused = false
        }
        // Resume physics
        physicsWorld.speed = 1
    }
    
    private func removePauseOverlay() {
        childNode(withName: "pauseOverlay")?.removeFromParent()
    }
    
    // Update your existing methods to check pause state
    override func update(_ currentTime: TimeInterval) {
        if isPaused { return }
        
        
        moveBackgroundStrip(speed: 0.6)
        
        // Your existing update logic
        // ...
    }
}
