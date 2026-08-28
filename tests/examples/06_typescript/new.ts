interface User {
  id: number;
  name: string;
  email: string;
  role: 'admin' | 'user' | 'guest';
  createdAt: Date;
}

interface CreateUserInput {
  name: string;
  email: string;
  role?: 'admin' | 'user' | 'guest';
}

type UserFilter = (user: User) => boolean;

class UserService {
  private users: Map<number, User> = new Map();
  private nextId: number = 1;

  addUser(input: CreateUserInput): User {
    const user: User = {
      id: this.nextId++,
      name: input.name,
      email: input.email,
      role: input.role ?? 'user',
      createdAt: new Date(),
    };
    this.users.set(user.id, user);
    return user;
  }

  getUser(id: number): User | undefined {
    return this.users.get(id);
  }

  updateUser(id: number, updates: Partial<Omit<User, 'id' | 'createdAt'>>): User | undefined {
    const user = this.users.get(id);
    if (!user) return undefined;
    Object.assign(user, updates);
    return user;
  }

  deleteUser(id: number): boolean {
    return this.users.delete(id);
  }

  getAll(filter?: UserFilter): User[] {
    const users = Array.from(this.users.values());
    return filter ? users.filter(filter) : users;
  }

  findByEmail(email: string): User | undefined {
    return this.getAll(u => u.email === email)[0];
  }
}

export { User, CreateUserInput, UserFilter, UserService };
