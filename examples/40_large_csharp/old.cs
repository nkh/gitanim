// MonoGameEngine.cs — Legacy monolithic 2D game engine.
// All entity logic, rendering, input, audio, and physics live in a single
// God class with switch statements dispatched on entity type.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace MonoGameEngine
{
    public enum EntityType
    {
        Player,
        Enemy,
        Projectile,
        Pickup,
        Wall,
        Trigger,
    }

    public enum EnemyState
    {
        Idle,
        Patrol,
        Chase,
        Attack,
        Dead,
    }

    public enum PickupKind
    {
        Health,
        Ammo,
        Key,
        ScoreBonus,
    }

    public class Entity
    {
        public int Id;
        public EntityType Type;
        public float X;
        public float Y;
        public float Width;
        public float Height;
        public float VelocityX;
        public float VelocityY;
        public int Health;
        public int MaxHealth;
        public EnemyState EnemyState;
        public PickupKind PickupKind;
        public int Score;
        public bool IsActive;
        public bool IsVisible;
        public string SpriteName;
        public Dictionary<string, object> CustomData;
    }

    public class GameEngine
    {
        private readonly List<Entity> _entities = new List<Entity>();
        private readonly Dictionary<int, Entity> _byId = new Dictionary<int, Entity>();
        private int _nextId = 1;

        public int Score;
        public int PlayerHealth;
        public int PlayerAmmo;
        public float PlayerX;
        public float PlayerY;
        public bool PlayerIsInvincible;
        public float PlayerInvincibleTimer;
        public float WorldWidth = 800;
        public float WorldHeight = 600;
        public float Gravity = 0.5f;

        private bool _leftPressed;
        private bool _rightPressed;
        private bool _upPressed;
        private bool _downPressed;
        private bool _firePressed;
        private float _fireCooldown;
        private float _elapsedTime;
        private readonly Random _rng = new Random();

        public Entity CreatePlayer(float x, float y)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Player,
                X = x,
                Y = y,
                Width = 32,
                Height = 48,
                Health = 100,
                MaxHealth = 100,
                IsActive = true,
                IsVisible = true,
                SpriteName = "player",
                CustomData = new Dictionary<string, object>(),
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            PlayerX = x;
            PlayerY = y;
            PlayerHealth = entity.Health;
            return entity;
        }

        public Entity CreateEnemy(float x, float y, int maxHealth)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Enemy,
                X = x,
                Y = y,
                Width = 28,
                Height = 28,
                Health = maxHealth,
                MaxHealth = maxHealth,
                EnemyState = EnemyState.Patrol,
                IsActive = true,
                IsVisible = true,
                SpriteName = "enemy",
                CustomData = new Dictionary<string, object>(),
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            return entity;
        }

        public Entity CreateProjectile(float x, float y, float vx, float vy)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Projectile,
                X = x,
                Y = y,
                Width = 8,
                Height = 4,
                VelocityX = vx,
                VelocityY = vy,
                IsActive = true,
                IsVisible = true,
                SpriteName = "projectile",
                CustomData = new Dictionary<string, object>(),
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            return entity;
        }

        public Entity CreatePickup(float x, float y, PickupKind kind)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Pickup,
                X = x,
                Y = y,
                Width = 16,
                Height = 16,
                PickupKind = kind,
                IsActive = true,
                IsVisible = true,
                SpriteName = "pickup_" + kind.ToString().ToLowerInvariant(),
                CustomData = new Dictionary<string, object>(),
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            return entity;
        }

        public Entity CreateWall(float x, float y, float w, float h)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Wall,
                X = x,
                Y = y,
                Width = w,
                Height = h,
                IsActive = true,
                IsVisible = true,
                SpriteName = "wall",
                CustomData = new Dictionary<string, object>(),
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            return entity;
        }

        public Entity CreateTrigger(float x, float y, float w, float h, string target)
        {
            var entity = new Entity
            {
                Id = _nextId++,
                Type = EntityType.Trigger,
                X = x,
                Y = y,
                Width = w,
                Height = h,
                IsActive = true,
                IsVisible = false,
                CustomData = new Dictionary<string, object> { { "target", target } },
            };
            _entities.Add(entity);
            _byId[entity.Id] = entity;
            return entity;
        }

        public void RemoveEntity(int id)
        {
            if (_byId.TryGetValue(id, out var entity))
            {
                _entities.Remove(entity);
                _byId.Remove(id);
            }
        }

        public Entity GetEntity(int id)
        {
            return _byId.TryGetValue(id, out var entity) ? entity : null;
        }

        public void SetInput(bool left, bool right, bool up, bool down, bool fire)
        {
            _leftPressed = left;
            _rightPressed = right;
            _upPressed = up;
            _downPressed = down;
            _firePressed = fire;
        }

        public void Update(float deltaTime)
        {
            _elapsedTime += deltaTime;
            if (_fireCooldown > 0) _fireCooldown -= deltaTime;
            if (PlayerInvincibleTimer > 0)
            {
                PlayerInvincibleTimer -= deltaTime;
                if (PlayerInvincibleTimer <= 0)
                {
                    PlayerIsInvincible = false;
                }
            }

            for (int i = _entities.Count - 1; i >= 0; i--)
            {
                var entity = _entities[i];
                if (!entity.IsActive) continue;
                switch (entity.Type)
                {
                    case EntityType.Player:
                        UpdatePlayer(entity, deltaTime);
                        break;
                    case EntityType.Enemy:
                        UpdateEnemy(entity, deltaTime);
                        break;
                    case EntityType.Projectile:
                        UpdateProjectile(entity, deltaTime);
                        break;
                    case EntityType.Pickup:
                        UpdatePickup(entity, deltaTime);
                        break;
                    case EntityType.Wall:
                        // Walls don't update.
                        break;
                    case EntityType.Trigger:
                        UpdateTrigger(entity);
                        break;
                }
            }

            // Collision pass.
            for (int i = 0; i < _entities.Count; i++)
            {
                var a = _entities[i];
                if (!a.IsActive) continue;
                for (int j = i + 1; j < _entities.Count; j++)
                {
                    var b = _entities[j];
                    if (!b.IsActive) continue;
                    if (Overlaps(a, b))
                    {
                        HandleCollision(a, b);
                    }
                }
            }

            // Cleanup pass.
            for (int i = _entities.Count - 1; i >= 0; i--)
            {
                var entity = _entities[i];
                if (!entity.IsActive && entity.Type != EntityType.Player)
                {
                    _entities.RemoveAt(i);
                    _byId.Remove(entity.Id);
                }
            }
        }

        private void UpdatePlayer(Entity entity, float dt)
        {
            float speed = 200f;
            if (_leftPressed) entity.VelocityX = -speed;
            else if (_rightPressed) entity.VelocityX = speed;
            else entity.VelocityX = 0;
            if (_upPressed) entity.VelocityY = -speed;
            else if (_downPressed) entity.VelocityY = speed;
            else entity.VelocityY = 0;

            entity.X += entity.VelocityX * dt;
            entity.Y += entity.VelocityY * dt;

            if (entity.X < 0) entity.X = 0;
            if (entity.Y < 0) entity.Y = 0;
            if (entity.X + entity.Width > WorldWidth) entity.X = WorldWidth - entity.Width;
            if (entity.Y + entity.Height > WorldHeight) entity.Y = WorldHeight - entity.Height;

            PlayerX = entity.X;
            PlayerY = entity.Y;
            entity.Health = PlayerHealth;

            if (_firePressed && PlayerAmmo > 0 && _fireCooldown <= 0)
            {
                CreateProjectile(entity.X + entity.Width, entity.Y + entity.Height / 2, 400f, 0f);
                PlayerAmmo--;
                _fireCooldown = 0.25f;
            }
        }

        private void UpdateEnemy(Entity entity, float dt)
        {
            switch (entity.EnemyState)
            {
                case EnemyState.Idle:
                    if (_rng.NextDouble() < 0.01)
                    {
                        entity.EnemyState = EnemyState.Patrol;
                        entity.CustomData["patrol_dir"] = _rng.Next(0, 4);
                    }
                    break;
                case EnemyState.Patrol:
                    int dir = entity.CustomData.ContainsKey("patrol_dir")
                        ? (int)entity.CustomData["patrol_dir"]
                        : 0;
                    float patrolSpeed = 60f;
                    switch (dir)
                    {
                        case 0: entity.VelocityX = patrolSpeed; entity.VelocityY = 0; break;
                        case 1: entity.VelocityX = -patrolSpeed; entity.VelocityY = 0; break;
                        case 2: entity.VelocityY = patrolSpeed; entity.VelocityX = 0; break;
                        case 3: entity.VelocityY = -patrolSpeed; entity.VelocityX = 0; break;
                    }
                    entity.X += entity.VelocityX * dt;
                    entity.Y += entity.VelocityY * dt;
                    if (_rng.NextDouble() < 0.02)
                    {
                        entity.CustomData["patrol_dir"] = _rng.Next(0, 4);
                    }
                    float distToPlayer = Math.Abs(entity.X - PlayerX) + Math.Abs(entity.Y - PlayerY);
                    if (distToPlayer < 200)
                    {
                        entity.EnemyState = EnemyState.Chase;
                    }
                    break;
                case EnemyState.Chase:
                    float dx = PlayerX - entity.X;
                    float dy = PlayerY - entity.Y;
                    float len = (float)Math.Sqrt(dx * dx + dy * dy);
                    if (len > 0)
                    {
                        entity.VelocityX = dx / len * 100f;
                        entity.VelocityY = dy / len * 100f;
                    }
                    entity.X += entity.VelocityX * dt;
                    entity.Y += entity.VelocityY * dt;
                    if (len > 400)
                    {
                        entity.EnemyState = EnemyState.Patrol;
                    }
                    else if (len < 40)
                    {
                        entity.EnemyState = EnemyState.Attack;
                        entity.CustomData["attack_cd"] = 0.5f;
                    }
                    break;
                case EnemyState.Attack:
                    float cd = entity.CustomData.ContainsKey("attack_cd")
                        ? (float)entity.CustomData["attack_cd"]
                        : 0f;
                    cd -= dt;
                    entity.CustomData["attack_cd"] = cd;
                    if (cd <= 0 && !PlayerIsInvincible)
                    {
                        PlayerHealth -= 10;
                        entity.CustomData["attack_cd"] = 1.0f;
                    }
                    float dx2 = PlayerX - entity.X;
                    float dy2 = PlayerY - entity.Y;
                    float len2 = (float)Math.Sqrt(dx2 * dx2 + dy2 * dy2);
                    if (len2 > 50) entity.EnemyState = EnemyState.Chase;
                    break;
                case EnemyState.Dead:
                    entity.IsActive = false;
                    break;
            }
        }

        private void UpdateProjectile(Entity entity, float dt)
        {
            entity.X += entity.VelocityX * dt;
            entity.Y += entity.VelocityY * dt;
            if (entity.X < 0 || entity.X > WorldWidth || entity.Y < 0 || entity.Y > WorldHeight)
            {
                entity.IsActive = false;
            }
        }

        private void UpdatePickup(Entity entity, float dt)
        {
            // Floating animation.
            entity.CustomData["bob_offset"] = Math.Sin(_elapsedTime * 4 + entity.Id) * 4;
        }

        private void UpdateTrigger(Entity entity)
        {
            // Handled in collision pass.
        }

        private void HandleCollision(Entity a, Entity b)
        {
            // Order-insensitive handling.
            Entity first = a.Type < b.Type ? a : b;
            Entity second = a.Type < b.Type ? b : a;

            switch (first.Type)
            {
                case EntityType.Player:
                    HandlePlayerCollision(first, second);
                    break;
                case EntityType.Enemy:
                    HandleEnemyCollision(first, second);
                    break;
                case EntityType.Projectile:
                    HandleProjectileCollision(first, second);
                    break;
                case EntityType.Pickup:
                    // Pickup-vs-non-player collisions are ignored.
                    break;
                case EntityType.Wall:
                    // Walls handled when player/enemy collide with them.
                    break;
                case EntityType.Trigger:
                    // Triggers handled when other entities collide with them.
                    break;
            }
        }

        private void HandlePlayerCollision(Entity player, Entity other)
        {
            switch (other.Type)
            {
                case EntityType.Enemy:
                    if (!PlayerIsInvincible && other.EnemyState != EnemyState.Dead)
                    {
                        PlayerHealth -= 5;
                        PlayerIsInvincible = true;
                        PlayerInvincibleTimer = 1.0f;
                    }
                    break;
                case EntityType.Pickup:
                    switch (other.PickupKind)
                    {
                        case PickupKind.Health:
                            PlayerHealth = Math.Min(100, PlayerHealth + 25);
                            break;
                        case PickupKind.Ammo:
                            PlayerAmmo += 10;
                            break;
                        case PickupKind.Key:
                            player.CustomData["has_key"] = true;
                            break;
                        case PickupKind.ScoreBonus:
                            Score += 100;
                            break;
                    }
                    other.IsActive = false;
                    break;
                case EntityType.Wall:
                    ResolveWallCollision(player, other);
                    break;
                case EntityType.Trigger:
                    string target = other.CustomData.ContainsKey("target")
                        ? (string)other.CustomData["target"]
                        : null;
                    if (target == "level_exit" && player.CustomData.ContainsKey("has_key"))
                    {
                        Score += 500;
                        other.IsActive = false;
                    }
                    break;
            }
        }

        private void HandleEnemyCollision(Entity enemy, Entity other)
        {
            switch (other.Type)
            {
                case EntityType.Wall:
                    ResolveWallCollision(enemy, other);
                    if (enemy.EnemyState == EnemyState.Patrol && enemy.CustomData.ContainsKey("patrol_dir"))
                    {
                        int dir = (int)enemy.CustomData["patrol_dir"];
                        enemy.CustomData["patrol_dir"] = (dir + 1) % 4;
                    }
                    break;
                case EntityType.Enemy:
                    // Enemies pass through each other.
                    break;
            }
        }

        private void HandleProjectileCollision(Entity projectile, Entity other)
        {
            switch (other.Type)
            {
                case EntityType.Enemy:
                    other.Health -= 25;
                    projectile.IsActive = false;
                    if (other.Health <= 0)
                    {
                        other.EnemyState = EnemyState.Dead;
                        other.IsActive = false;
                        Score += 50;
                    }
                    break;
                case EntityType.Wall:
                    projectile.IsActive = false;
                    break;
            }
        }

        private void ResolveWallCollision(Entity mover, Entity wall)
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
            if (mover.Type == EntityType.Player)
            {
                PlayerX = mover.X;
                PlayerY = mover.Y;
            }
        }

        private bool Overlaps(Entity a, Entity b)
        {
            return a.X < b.X + b.Width && a.X + a.Width > b.X
                && a.Y < b.Y + b.Height && a.Y + a.Height > b.Y;
        }

        public void Render(IGraphics graphics)
        {
            graphics.Clear(Color.Black);
            foreach (var entity in _entities)
            {
                if (!entity.IsVisible) continue;
                float drawY = entity.Y;
                if (entity.Type == EntityType.Pickup && entity.CustomData.ContainsKey("bob_offset"))
                {
                    drawY += (float)entity.CustomData["bob_offset"];
                }
                switch (entity.Type)
                {
                    case EntityType.Player:
                        graphics.DrawSprite(entity.SpriteName, entity.X, drawY,
                            PlayerIsInvincible && (int)(_elapsedTime * 20) % 2 == 0 ? 0.5f : 1f);
                        graphics.DrawHealthBar(entity.X, entity.Y - 8, entity.Width, 4,
                            PlayerHealth, 100);
                        break;
                    case EntityType.Enemy:
                        graphics.DrawSprite(entity.SpriteName, entity.X, drawY, 1f);
                        graphics.DrawHealthBar(entity.X, entity.Y - 8, entity.Width, 3,
                            entity.Health, entity.MaxHealth);
                        break;
                    case EntityType.Projectile:
                        graphics.DrawSprite(entity.SpriteName, entity.X, drawY, 1f);
                        break;
                    case EntityType.Pickup:
                        graphics.DrawSprite(entity.SpriteName, entity.X, drawY, 1f);
                        break;
                    case EntityType.Wall:
                        graphics.DrawRect(entity.X, entity.Y, entity.Width, entity.Height,
                            Color.DarkGray);
                        break;
                    case EntityType.Trigger:
                        // Invisible.
                        break;
                }
            }
            graphics.DrawText("Score: " + Score, 8, 8, Color.White);
            graphics.DrawText("Health: " + PlayerHealth, 8, 28, Color.White);
            graphics.DrawText("Ammo: " + PlayerAmmo, 8, 48, Color.White);
        }

        public List<Entity> GetEntitiesInRadius(float cx, float cy, float radius)
        {
            var result = new List<Entity>();
            foreach (var entity in _entities)
            {
                if (!entity.IsActive) continue;
                float dx = entity.X + entity.Width / 2 - cx;
                float dy = entity.Y + entity.Height / 2 - cy;
                if (dx * dx + dy * dy <= radius * radius)
                {
                    result.Add(entity);
                }
            }
            return result;
        }

        public List<Entity> GetEntitiesByType(EntityType type)
        {
            return _entities.Where(e => e.Type == type && e.IsActive).ToList();
        }

        public int CountActiveEnemies()
        {
            int count = 0;
            foreach (var e in _entities)
            {
                if (e.Type == EntityType.Enemy && e.EnemyState != EnemyState.Dead && e.IsActive)
                {
                    count++;
                }
            }
            return count;
        }

        public void ApplySplashDamage(float cx, float cy, float radius, int damage)
        {
            foreach (var entity in GetEntitiesInRadius(cx, cy, radius))
            {
                if (entity.Type == EntityType.Enemy)
                {
                    entity.Health -= damage;
                    if (entity.Health <= 0)
                    {
                        entity.EnemyState = EnemyState.Dead;
                        entity.IsActive = false;
                        Score += 50;
                    }
                }
            }
        }

        public void SaveState()
        {
            // No-op in this stub.
        }

        public void LoadState()
        {
            // No-op in this stub.
        }
    }

    public interface IGraphics
    {
        void Clear(Color color);
        void DrawSprite(string name, float x, float y, float alpha);
        void DrawRect(float x, float y, float w, float h, Color color);
        void DrawText(string text, float x, float y, Color color);
        void DrawHealthBar(float x, float y, float w, float h, int current, int max);
    }

    public class NullGraphics : IGraphics
    {
        public void Clear(Color color) { }
        public void DrawSprite(string name, float x, float y, float alpha) { }
        public void DrawRect(float x, float y, float w, float h, Color color) { }
        public void DrawText(string text, float x, float y, Color color) { }
        public void DrawHealthBar(float x, float y, float w, float h, int current, int max) { }
    }
}
