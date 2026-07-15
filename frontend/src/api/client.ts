const API_BASE_URL = import.meta.env.VITE_API_BASE_URL as string;

export interface User {
  id: string;
  email: string;
  name: string;
  picture: string;
}

export interface LoginResponse {
  token: string;
  expires_at: number;
  user: User;
}

export interface GmailMessage {
  id: string;
  subject: string;
  from: string;
  snippet: string;
}

export interface Label {
  id: string;
  name: string;
  description: string;
  created_at: string;
  updated_at: string;
}

async function parseJsonOrThrow(response: Response) {
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error ?? `Request failed with status ${response.status}`);
  }
  return data;
}

export async function loginWithGoogle(code: string): Promise<LoginResponse> {
  const response = await fetch(`${API_BASE_URL}/auth/google`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code }),
  });
  return parseJsonOrThrow(response);
}

export async function fetchMe(token: string): Promise<User> {
  const response = await fetch(`${API_BASE_URL}/auth/me`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return parseJsonOrThrow(response);
}

export async function fetchGmailMessages(token: string): Promise<GmailMessage[]> {
  const response = await fetch(`${API_BASE_URL}/gmail/messages`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = await parseJsonOrThrow(response);
  return data.messages;
}

export async function fetchLabels(token: string): Promise<Label[]> {
  const response = await fetch(`${API_BASE_URL}/labels`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = await parseJsonOrThrow(response);
  return data.labels;
}

export async function createLabel(token: string, name: string, description: string): Promise<Label> {
  const response = await fetch(`${API_BASE_URL}/labels`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name, description }),
  });
  return parseJsonOrThrow(response);
}

export async function updateLabel(token: string, id: string, name: string, description: string): Promise<Label> {
  const response = await fetch(`${API_BASE_URL}/labels/${id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name, description }),
  });
  return parseJsonOrThrow(response);
}

export async function deleteLabel(token: string, id: string): Promise<void> {
  const response = await fetch(`${API_BASE_URL}/labels/${id}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  await parseJsonOrThrow(response);
}
