// EcsGameEngine.cs — Refactored 2D game engine using the Entity-Component-
// System (ECS) pattern. Components are plain data; systems operate on
// queries over components. Subsystems are wired up via dependency injection.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace EcsGameEngine
{
    // ------------------------------------------------------------------
    // Core ECS primitives
    // ------------------------------------------------------------------

    public readonly struct EntityId : IEquatable<EntityId>
    {
        public readonly int Value;
        public EntityId(int value) { Value = value; }
        public bool Equals(EntityId other) => Value == other.Value;
        public override bool Equals(object obj) => obj is EntityId id && Equals(id);
        public override int GetHashCode() => Value;
        public static bool operator ==(EntityId a, EntityId b) => a.Value == b.Value;
        public static bool operator !=(EntityId a, EntityId b) => a.Value != b.Value;
        public override string ToString() => $"Entity({Value})";
    }

    public interface IComponent { }

    public sealed class TransformComponent : IComponent
    {
        public float X, Y;
        public float Width, Height;
        public TransformComponent(float x, float y, float w, float h)
        { X = x; Y = y; Width = w; Height = h; }
    }

    public sealed class VelocityComponent : IComponent
    {
        public float Vx, Vy;
        public VelocityComponent(float vx, float vy) { Vx = vx; Vy = vy; }
    }

    public sealed class HealthComponent : IComponent
    {
        public int Current, Max;
        public HealthComponent(int max) { Current = max; Max = max; }
    }

    public sealed class SpriteComponent : IComponent
    {
        public string Name;
        public float Alpha = 1f;
        public SpriteComponent(string name) { Name = name; }
    }

    public sealed class PlayerComponent : IComponent
    {
        public int Ammo = 30;
        public float FireCooldown;
        public bool IsInvincible;
        public float InvincibleTimer;
        public bool HasKey;
    }

    public sealed class EnemyComponent : IComponent
    {
        public EnemyState State = EnemyState.Patrol;
        public int PatrolDirection;
        public float AttackCooldown;
        public float DetectRadius = 200f;
        public float LoseRadius = 400f;
        public float AttackRange = 40f;
        public float PatrolSpeed = 60f;
        public float ChaseSpeed = 100f;
        public int AttackDamage = 10;
    }

    public sealed class ProjectileComponent : IComponent
    {
        public int Damage = 25;
        public EntityId Source;
        public ProjectileComponent(EntityId source) { Source = source; }
    }

    public sealed class PickupComponent : IComponent
    {
        public PickupKind Kind;
        public int Amount;
        public PickupComponent(PickupKind kind, int amount) { Kind = kind; Amount = amount; }
    }

    public sealed class SolidComponent : IComponent { }

    public sealed class TriggerComponent : IComponent
    {
        public string EventName;
        public bool OneShot = true;
        public bool Fired;
        public TriggerComponent(string name) { EventName = name; }
    }

    public enum EnemyState { Idle, Patrol, Chase, Attack, Dead }
    public enum PickupKind { Health, Ammo, Key, ScoreBonus }

    // ------------------------------------------------------------------
    // World (entity/component storage)
    // ------------------------------------------------------------------

    public sealed class World
    {
        private int _nextId = 1;
        private readonly Dictionary<Type, Dictionary<EntityId, IComponent>> _stores
            = new Dictionary<Type, Dictionary<EntityId, IComponent>>();
        private readonly HashSet<EntityId> _entities = new HashSet<EntityId>();
        private readonly List<EntityId> _removalQueue = new List<EntityId>();

        public IEnumerable<EntityId> Entities => _entities;

        public EntityId CreateEntity()
        {
            var id = new EntityId(_nextId++);
            _entities.Add(id);
            return id;
        }

        public void AddComponent<T>(EntityId id, T component) where T : IComponent
        {
            var type = typeof(T);
            if (!_stores.TryGetValue(type, out var store))
            {
                store = new Dictionary<EntityId, IComponent>();
                _stores[type] = store;
            }
            store[id] = component;
        }

        public T GetComponent<T>(EntityId id) where T : class, IComponent
        {
            if (_stores.TryGetValue(typeof(T), out var store) && store.TryGetValue(id, out var c))
            {
                return (T)c;
            }
            return null;
        }

        public bool HasComponent<T>(EntityId id) where T : IComponent
        {
            return _stores.TryGetValue(typeof(T), out var store) && store.ContainsKey(id);
        }

        public void RemoveComponent<T>(EntityId id) where T : IComponent
        {
            if (_stores.TryGetValue(typeof(T), out var store))
            {
                store.Remove(id);
            }
        }

        public void RemoveEntity(EntityId id)
        {
            _removalQueue.Add(id);
        }

        public IEnumerable<EntityId> Query<T1>() where T1 : IComponent
        {
            foreach (var id in _entities)
            {
                if (HasComponent<T1>(id)) yield return id;
            }
        }

        public IEnumerable<EntityId> Query<T1, T2>()
            where T1 : IComponent
            where T2 : IComponent
        {
            foreach (var id in _entities)
            {
                if (HasComponent<T1>(id) && HasComponent<T2>(id)) yield return id;
            }
        }

        public IEnumerable<EntityId> Query<T1, T2, T3>()
            where T1 : IComponent
            where T2 : IComponent
            where T3 : IComponent
        {
            foreach (var id in _entities)
            {
                if (HasComponent<T1>(id) && HasComponent<T2>(id) && HasComponent<T3>(id))
                    yield return id;
            }
        }

        public void FlushRemovals()
        {
            if (_removalQueue.Count == 0) return;
            foreach (var id in _removalQueue)
            {
                _entities.Remove(id);
                foreach (var store in _stores.Values) store.Remove(id);
            }
            _removalQueue.Clear();
        }
    }

    // ------------------------------------------------------------------
    // Game state shared across systems
    // ------------------------------------------------------------------

    public sealed class GameState
    {
        public int Score;
        public float WorldWidth = 800f;
        public float WorldHeight = 600f;
        public float ElapsedTime;
        public readonly Random Rng = new Random();
        public EntityId? PlayerId;
    }

    public interface IInputState
    {
        bool Left { get; }
        bool Right { get; }
        bool Up { get; }
        bool Down { get; }
        bool Fire { get; }
    }

    public sealed class DefaultInputState : IInputState
    {
        public bool Left, Right, Up, Down, Fire;
        bool IInputState.Left => Left;
        bool IInputState.Right => Right;
        bool IInputState.Up => Up;
        bool IInputState.Down => Down;
        bool IInputState.Fire => Fire;
    }

    // ------------------------------------------------------------------
    // Interfaces for systems
    // ------------------------------------------------------------------

    public interface IGameSystem
    {
        void Update(float deltaTime);
    }

    public interface IRenderSystem
    {
        void Render(IGraphics graphics);
    }

    public interface IGraphics
    {
        void Clear(Color color);
        void DrawSprite(string name, float x, float y, float alpha);
        void DrawRect(float x, float y, float w, float h, Color color);
        void DrawText(string text, float x, float y, Color color);
        void DrawHealthBar(float x, float y, float w, float h, int current, int max);
    }

    // ------------------------------------------------------------------
    // Systems
    // ------------------------------------------------------------------

    public sealed class PlayerControlSystem : IGameSystem
    {
        private readonly World _world;
        private readonly GameState _state;
        private readonly IInputState _input;
        private readonly Action<EntityId, float, float, float, float> _spawnProjectile;

        public PlayerControlSystem(World world, GameState state, IInputState input,
            Action<EntityId, float, float, float, float> spawnProjectile)
        {
            _world = world;
            _state = state;
            _input = input;
            _spawnProjectile = spawnProjectile;
        }

        public void Update(float dt)
        {
            if (!_state.PlayerId.HasValue) return;
            var id = _state.PlayerId.Value;
            var transform = _world.GetComponent<TransformComponent>(id);
            var velocity = _world.GetComponent<VelocityComponent>(id);
            var player = _world.GetComponent<PlayerComponent>(id);
            if (transform == null || velocity == null || player == null) return;

            const float speed = 200f;
            velocity.Vx = _input.Left ? -speed : (_input.Right ? speed : 0);
            velocity.Vy = _input.Up ? -speed : (_input.Down ? speed : 0);

            if (player.FireCooldown > 0) player.FireCooldown -= dt;
            if (player.InvincibleTimer > 0)
            {
                player.InvincibleTimer -= dt;
                if (player.InvincibleTimer <= 0) player.IsInvincible = false;
            }
            if (_input.Fire && player.Ammo > 0 && player.FireCooldown <= 0)
            {
                _spawnProjectile(id,
                    transform.X + transform.Width,
                    transform.Y + transform.Height / 2f,
                    400f, 0f);
                player.Ammo--;
                player.FireCooldown = 0.25f;
            }
        }
    }

    public sealed class MovementSystem : IGameSystem
    {
        private readonly World _world;
        private readonly GameState _state;

        public MovementSystem(World world, GameState state)
        {
            _world = world;
            _state = state;
        }

        public void Update(float dt)
        {
            foreach (var id in _world.Query<TransformComponent, VelocityComponent>())
            {
                var t = _world.GetComponent<TransformComponent>(id);
                var v = _world.GetComponent<VelocityComponent>(id);
                t.X += v.Vx * dt;
                t.Y += v.Vy * dt;
                if (t.X < 0) t.X = 0;
                if (t.Y < 0) t.Y = 0;
                if (t.X + t.Width > _state.WorldWidth) t.X = _state.WorldWidth - t.Width;
                if (t.Y + t.Height > _state.WorldHeight) t.Y = _state.WorldHeight - t.Height;
            }
        }
    }

    public sealed class ProjectileLifetimeSystem : IGameSystem
    {
        private readonly World _world;
        private readonly GameState _state;

        public ProjectileLifetimeSystem(World world, GameState state)
        {
            _world = world;
            _state = state;
        }

        public void Update(float dt)
        {
            foreach (var id in _world.Query<TransformComponent, ProjectileComponent>())
            {
                var t = _world.GetComponent<TransformComponent>(id);
                if (t.X < 0 || t.X > _state.WorldWidth ||
                    t.Y < 0 || t.Y > _state.WorldHeight)
                {
                    _world.RemoveEntity(id);
                }
            }
        }
    }

    public sealed class EnemyAiSystem : IGameSystem
    {
        private readonly World _world;
        private readonly GameState _state;

        public EnemyAiSystem(World world, GameState state)
        {
            _world = world;
            _state = state;
        }

        public void Update(float dt)
        {
            if (!_state.PlayerId.HasValue) return;
            var playerId = _state.PlayerId.Value;
            var playerTransform = _world.GetComponent<TransformComponent>(playerId);
            if (playerTransform == null) return;

            foreach (var id in _world.Query<TransformComponent, EnemyComponent>())
            {
                var t = _world.GetComponent<TransformComponent>(id);
                var v = _world.GetComponent<VelocityComponent>(id);
                var enemy = _world.GetComponent<EnemyComponent>(id);
                if (v == null) continue;

                float dx = playerTransform.X - t.X;
                float dy = playerTransform.Y - t.Y;
                float dist = (float)Math.Sqrt(dx * dx + dy * dy);

                switch (enemy.State)
                {
                    case EnemyState.Idle:
                        if (_state.Rng.NextDouble() < 0.01)
                        {
                            enemy.State = EnemyState.Patrol;
                            enemy.PatrolDirection = _state.Rng.Next(0, 4);
                        }
                        break;
                    case EnemyState.Patrol:
                        switch (enemy.PatrolDirection)
                        {
                            case 0: v.Vx = enemy.PatrolSpeed; v.Vy = 0; break;
                            case 1: v.Vx = -enemy.PatrolSpeed; v.Vy = 0; break;
                            case 2: v.Vx = 0; v.Vy = enemy.PatrolSpeed; break;
                            case 3: v.Vx = 0; v.Vy = -enemy.PatrolSpeed; break;
                        }
                        if (_state.Rng.NextDouble() < 0.02)
                        {
                            enemy.PatrolDirection = _state.Rng.Next(0, 4);
                        }
                        if (dist < enemy.DetectRadius)
                        {
                            enemy.State = EnemyState.Chase;
                        }
                        break;
                    case EnemyState.Chase:
                        if (dist > 0)
                        {
                            v.Vx = dx / dist * enemy.ChaseSpeed;
                            v.Vy = dy / dist * enemy.ChaseSpeed;
                        }
                        if (dist > enemy.LoseRadius)
                        {
                            enemy.State = EnemyState.Patrol;
                        }
                        else if (dist < enemy.AttackRange)
                        {
                            enemy.State = EnemyState.Attack;
                            enemy.AttackCooldown = 0.5f;
                        }
                        break;
                    case EnemyState.Attack:
                        enemy.AttackCooldown -= dt;
                        var player = _world.GetComponent<PlayerComponent>(playerId);
                        var health = _world.GetComponent<HealthComponent>(playerId);
                        if (enemy.AttackCooldown <= 0 && player != null && !player.IsInvincible
                            && health != null)
                        {
                            health.Current -= enemy.AttackDamage;
                            player.IsInvincible = true;
                            player.InvincibleTimer = 1.0f;
                            enemy.AttackCooldown = 1.0f;
                        }
                        if (dist > enemy.AttackRange * 1.5f)
                        {
                            enemy.State = EnemyState.Chase;
                        }
                        break;
                    case EnemyState.Dead:
                        _world.RemoveEntity(id);
                        break;
                }
            }
        }
    }

    public sealed class CollisionSystem : IGameSystem
    {
        private readonly World _world;
        private readonly GameState _state;

        public CollisionSystem(World world, GameState state)
        {
            _world = world;
            _state = state;
        }

        public void Update(float dt)
        {
            var mobile = _world.Query<TransformComponent>().ToList();
            var solids = _world.Query<TransformComponent, SolidComponent>().ToList();
            foreach (var id in mobile)
            {
                var t = _world.GetComponent<TransformComponent>(id);
                foreach (var wallId in solids)
                {
                    if (id == wallId) continue;
                    var wall = _world.GetComponent<TransformComponent>(wallId);
                    if (Overlaps(t, wall))
                    {
                        ResolveWallCollision(t, wall);
                        // Bounce patrol enemies.
                        var enemy = _world.GetComponent<EnemyComponent>(id);
                        if (enemy != null && enemy.State == EnemyState.Patrol)
                        {
                            enemy.PatrolDirection = (enemy.PatrolDirection + 1) % 4;
                        }
                    }
                }
            }

            // Projectile-vs-enemy collisions.
            var projectiles = _world.Query<TransformComponent, ProjectileComponent>().ToList();
            var enemies = _world.Query<TransformComponent, EnemyComponent, HealthComponent>().ToList();
            foreach (var projId in projectiles)
            {
                var pt = _world.GetComponent<TransformComponent>(projId);
                var proj = _world.GetComponent<ProjectileComponent>(projId);
                foreach (var enemyId in enemies)
                {
                    var et = _world.GetComponent<TransformComponent>(enemyId);
                    var health = _world.GetComponent<HealthComponent>(enemyId);
                    if (Overlaps(pt, et))
                    {
                        health.Current -= proj.Damage;
                        _world.RemoveEntity(projId);
                        if (health.Current <= 0)
                        {
                            var enemy = _world.GetComponent<EnemyComponent>(enemyId);
                            enemy.State = EnemyState.Dead;
                            _state.Score += 50;
                        }
                        break;
                    }
                }
            }

            // Player-vs-pickup and player-vs-trigger collisions.
            if (_state.PlayerId.HasValue)
            {
                var playerId = _state.PlayerId.Value;
                var playerT = _world.GetComponent<TransformComponent>(playerId);
                if (playerT != null)
                {
                    foreach (var pickupId in _world.Query<TransformComponent, PickupComponent>().ToList())
                    {
                        var pt2 = _world.GetComponent<TransformComponent>(pickupId);
                        if (Overlaps(playerT, pt2))
                        {
                            ApplyPickup(playerId, pickupId);
                        }
                    }
                    foreach (var triggerId in _world.Query<TransformComponent, TriggerComponent>().ToList())
                    {
                        var tt = _world.GetComponent<TransformComponent>(triggerId);
                        var trigger = _world.GetComponent<TriggerComponent>(triggerId);
                        if (Overlaps(playerT, tt))
                        {
                            FireTrigger(playerId, triggerId, trigger);
                        }
                    }
                }
            }
        }

        private void ApplyPickup(EntityId playerId, EntityId pickupId)
        {
            var pickup = _world.GetComponent<PickupComponent>(pickupId);
            var player = _world.GetComponent<PlayerComponent>(playerId);
            var health = _world.GetComponent<HealthComponent>(playerId);
            switch (pickup.Kind)
            {
                case PickupKind.Health:
                    if (health != null) health.Current = Math.Min(health.Max, health.Current + pickup.Amount);
                    break;
                case PickupKind.Ammo:
                    if (player != null) player.Ammo += pickup.Amount;
                    break;
                case PickupKind.Key:
                    if (player != null) player.HasKey = true;
                    break;
                case PickupKind.ScoreBonus:
                    _state.Score += pickup.Amount;
                    break;
            }
            _world.RemoveEntity(pickupId);
        }

        private void FireTrigger(EntityId playerId, EntityId triggerId, TriggerComponent trigger)
        {
            if (trigger.Fired && trigger.OneShot) return;
            var player = _world.GetComponent<PlayerComponent>(playerId);
            switch (trigger.EventName)
            {
                case "level_exit":
                    if (player != null && player.HasKey)
                    {
                        _state.Score += 500;
                        trigger.Fired = true;
                        _world.RemoveEntity(triggerId);
                    }
                    break;
                case "secret_area":
                    _state.Score += 250;
                    trigger.Fired = true;
                    break;
            }
        }

        private static bool Overlaps(TransformComponent a, TransformComponent b)
        {
            return a.X < b.X + b.Width && a.X + a.Width > b.X
                && a.Y < b.Y + b.Height && a.Y + a.Height > b.Y;
        }

        private static void ResolveWallCollision(TransformComponent mover, TransformComponent wall)
        {
            float dx = (mover.X + mover.Width / 2) - (wall.X + wall.Width / 2);
            float dy = (mover.Y + mover.Height / 2) - (wall.Y + wall.Height / 2);
            float overlapX = (mover.Width + wall.Width) / 2 - Math.Abs(dx);
            float overlapY = (mover.Height + wall.Height) / 2 - Math.Abs(dy);
            if (overlapX < overlapY)
            {
                mover.X += dx > 0 ? overlapX : -overlapX;
            }
            else
            {
                mover.Y += dy > 0 ? overlapY : -overlapY;
            }
        }
    }

    public sealed class RenderSystem : IRenderSystem
    {
        private readonly World _world;
        private readonly GameState _state;

        public RenderSystem(World world, GameState state)
        {
            _world = world;
            _state = state;
        }

        public void Render(IGraphics graphics)
        {
            graphics.Clear(Color.Black);
            foreach (var id in _world.Entities)
            {
                var transform = _world.GetComponent<TransformComponent>(id);
                if (transform == null) continue;
                var sprite = _world.GetComponent<SpriteComponent>(id);
                float drawY = transform.Y;
                if (sprite != null)
                {
                    float alpha = sprite.Alpha;
                    var player = _world.GetComponent<PlayerComponent>(id);
                    if (player != null && player.IsInvincible &&
                        (int)(_state.ElapsedTime * 20) % 2 == 0)
                    {
                        alpha = 0.5f;
                    }
                    graphics.DrawSprite(sprite.Name, transform.X, drawY, alpha);
                }
                else if (_world.HasComponent<SolidComponent>(id))
                {
                    graphics.DrawRect(transform.X, transform.Y, transform.Width, transform.Height,
                        Color.DarkGray);
                }
                var health = _world.GetComponent<HealthComponent>(id);
                if (health != null)
                {
                    graphics.DrawHealthBar(transform.X, transform.Y - 8,
                        transform.Width, 4, health.Current, health.Max);
                }
            }
            graphics.DrawText("Score: " + _state.Score, 8, 8, Color.White);
            if (_state.PlayerId.HasValue)
            {
                var health = _world.GetComponent<HealthComponent>(_state.PlayerId.Value);
                var player = _world.GetComponent<PlayerComponent>(_state.PlayerId.Value);
                if (health != null)
                    graphics.DrawText("Health: " + health.Current, 8, 28, Color.White);
                if (player != null)
                    graphics.DrawText("Ammo: " + player.Ammo, 8, 48, Color.White);
            }
        }
    }

    // ------------------------------------------------------------------
    // Game engine facade
    // ------------------------------------------------------------------

    public sealed class GameEngine
    {
        private readonly World _world;
        private readonly GameState _state;
        private readonly List<IGameSystem> _updateSystems = new List<IGameSystem>();
        private readonly List<IRenderSystem> _renderSystems = new List<IRenderSystem>();

        public int Score => _state.Score;

        public GameEngine(World world, GameState state, IInputState input)
        {
            _world = world;
            _state = state;
            // Wire up systems with their dependencies.
            _updateSystems.Add(new PlayerControlSystem(world, state, input, SpawnProjectile));
            _updateSystems.Add(new MovementSystem(world, state));
            _updateSystems.Add(new ProjectileLifetimeSystem(world, state));
            _updateSystems.Add(new EnemyAiSystem(world, state));
            _updateSystems.Add(new CollisionSystem(world, state));
            _renderSystems.Add(new RenderSystem(world, state));
        }

        public EntityId SpawnPlayer(float x, float y)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, 32, 48));
            _world.AddComponent(id, new VelocityComponent(0, 0));
            _world.AddComponent(id, new HealthComponent(100));
            _world.AddComponent(id, new SpriteComponent("player"));
            _world.AddComponent(id, new PlayerComponent());
            _state.PlayerId = id;
            return id;
        }

        public EntityId SpawnEnemy(float x, float y, int maxHealth)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, 28, 28));
            _world.AddComponent(id, new VelocityComponent(0, 0));
            _world.AddComponent(id, new HealthComponent(maxHealth));
            _world.AddComponent(id, new SpriteComponent("enemy"));
            _world.AddComponent(id, new EnemyComponent());
            return id;
        }

        public EntityId SpawnProjectile(EntityId source, float x, float y, float vx, float vy)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, 8, 4));
            _world.AddComponent(id, new VelocityComponent(vx, vy));
            _world.AddComponent(id, new SpriteComponent("projectile"));
            _world.AddComponent(id, new ProjectileComponent(source));
            return id;
        }

        public EntityId SpawnPickup(float x, float y, PickupKind kind, int amount)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, 16, 16));
            _world.AddComponent(id, new SpriteComponent("pickup_" + kind.ToString().ToLowerInvariant()));
            _world.AddComponent(id, new PickupComponent(kind, amount));
            return id;
        }

        public EntityId SpawnWall(float x, float y, float w, float h)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, w, h));
            _world.AddComponent(id, new SolidComponent());
            return id;
        }

        public EntityId SpawnTrigger(float x, float y, float w, float h, string eventName)
        {
            var id = _world.CreateEntity();
            _world.AddComponent(id, new TransformComponent(x, y, w, h));
            _world.AddComponent(id, new TriggerComponent(eventName));
            return id;
        }

        public void Update(float dt)
        {
            _state.ElapsedTime += dt;
            foreach (var system in _updateSystems) system.Update(dt);
            _world.FlushRemovals();
        }

        public void Render(IGraphics graphics)
        {
            foreach (var system in _renderSystems) system.Render(graphics);
        }

        public void ApplySplashDamage(float cx, float cy, float radius, int damage)
        {
            var enemies = _world.Query<TransformComponent, HealthComponent, EnemyComponent>().ToList();
            foreach (var id in enemies)
            {
                var t = _world.GetComponent<TransformComponent>(id);
                var health = _world.GetComponent<HealthComponent>(id);
                var enemy = _world.GetComponent<EnemyComponent>(id);
                float dx = t.X + t.Width / 2 - cx;
                float dy = t.Y + t.Height / 2 - cy;
                if (dx * dx + dy * dy <= radius * radius)
                {
                    health.Current -= damage;
                    if (health.Current <= 0)
                    {
                        enemy.State = EnemyState.Dead;
                        _state.Score += 50;
                    }
                }
            }
        }

        public int CountActiveEnemies()
        {
            int count = 0;
            foreach (var id in _world.Query<EnemyComponent>())
            {
                var enemy = _world.GetComponent<EnemyComponent>(id);
                if (enemy.State != EnemyState.Dead) count++;
            }
            return count;
        }
    }

    // ------------------------------------------------------------------
    // NullGraphics for testing
    // ------------------------------------------------------------------

    public sealed class NullGraphics : IGraphics
    {
        public void Clear(Color color) { }
        public void DrawSprite(string name, float x, float y, float alpha) { }
        public void DrawRect(float x, float y, float w, float h, Color color) { }
        public void DrawText(string text, float x, float y, Color color) { }
        public void DrawHealthBar(float x, float y, float w, float h, int current, int max) { }
    }
}
