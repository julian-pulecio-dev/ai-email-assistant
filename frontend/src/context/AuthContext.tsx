import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { fetchMe, loginWithGoogle, type User } from "../api/client";

const TOKEN_STORAGE_KEY = "session_token";

interface AuthContextValue {
  user: User | null;
  token: string | null;
  loading: boolean;
  error: string | null;
  loginWithGoogleAuthCode: (code: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const storedToken = localStorage.getItem(TOKEN_STORAGE_KEY);
    if (!storedToken) {
      setLoading(false);
      return;
    }
    fetchMe(storedToken)
      .then((fetchedUser) => {
        setUser(fetchedUser);
        setToken(storedToken);
      })
      .catch(() => localStorage.removeItem(TOKEN_STORAGE_KEY))
      .finally(() => setLoading(false));
  }, []);

  async function loginWithGoogleAuthCode(code: string) {
    setError(null);
    try {
      const response = await loginWithGoogle(code);
      localStorage.setItem(TOKEN_STORAGE_KEY, response.token);
      setToken(response.token);
      setUser(response.user);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
      throw err;
    }
  }

  function logout() {
    localStorage.removeItem(TOKEN_STORAGE_KEY);
    setToken(null);
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, token, loading, error, loginWithGoogleAuthCode, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
