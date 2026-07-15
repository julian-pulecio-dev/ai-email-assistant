import { useEffect, useState, type FormEvent } from "react";
import { createLabel, deleteLabel, fetchLabels, updateLabel, type Label } from "../api/client";
import { useAuth } from "../context/AuthContext";

export function LabelsManager() {
  const { token } = useAuth();
  const [labels, setLabels] = useState<Label[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [creating, setCreating] = useState(false);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editDescription, setEditDescription] = useState("");
  const [savingEditId, setSavingEditId] = useState<string | null>(null);

  const [deletingId, setDeletingId] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    fetchLabels(token)
      .then(setLabels)
      .catch(() => setError("Could not load categories."));
  }, [token]);

  if (!token) {
    return null;
  }

  async function handleCreate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setCreating(true);
    try {
      const label = await createLabel(token!, newName.trim(), newDescription.trim());
      setLabels((prev) => [...(prev ?? []), label]);
      setNewName("");
      setNewDescription("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create category.");
    } finally {
      setCreating(false);
    }
  }

  function startEditing(label: Label) {
    setEditingId(label.id);
    setEditName(label.name);
    setEditDescription(label.description);
  }

  async function handleSaveEdit(event: FormEvent, id: string) {
    event.preventDefault();
    setError(null);
    setSavingEditId(id);
    try {
      const updated = await updateLabel(token!, id, editName.trim(), editDescription.trim());
      setLabels((prev) => (prev ?? []).map((label) => (label.id === id ? updated : label)));
      setEditingId(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update category.");
    } finally {
      setSavingEditId(null);
    }
  }

  async function handleDelete(id: string) {
    setError(null);
    setDeletingId(id);
    try {
      await deleteLabel(token!, id);
      setLabels((prev) => (prev ?? []).filter((label) => label.id !== id));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not delete category.");
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <div className="labels-manager">
      <h2>Email categories</h2>
      <p className="hint">
        Categories the assistant sorts your incoming email into. Each one also creates a matching label in Gmail.
      </p>

      {error && <p className="error">{error}</p>}

      {labels === null ? (
        <p>Loading...</p>
      ) : labels.length === 0 ? (
        <p>No categories yet.</p>
      ) : (
        <ul className="labels-list">
          {labels.map((label) =>
            editingId === label.id ? (
              <li key={label.id}>
                <form className="label-form" onSubmit={(event) => handleSaveEdit(event, label.id)}>
                  <input value={editName} onChange={(event) => setEditName(event.target.value)} required />
                  <textarea
                    value={editDescription}
                    onChange={(event) => setEditDescription(event.target.value)}
                    required
                  />
                  <div className="label-actions">
                    <button type="submit" disabled={savingEditId === label.id}>
                      {savingEditId === label.id ? "Saving..." : "Save"}
                    </button>
                    <button type="button" onClick={() => setEditingId(null)}>
                      Cancel
                    </button>
                  </div>
                </form>
              </li>
            ) : (
              <li key={label.id}>
                <strong>{label.name}</strong>
                <p>{label.description}</p>
                <div className="label-actions">
                  <button onClick={() => startEditing(label)}>Edit</button>
                  <button onClick={() => handleDelete(label.id)} disabled={deletingId === label.id}>
                    {deletingId === label.id ? "Deleting..." : "Delete"}
                  </button>
                </div>
              </li>
            ),
          )}
        </ul>
      )}

      <form className="label-form" onSubmit={handleCreate}>
        <h3>Add category</h3>
        <input
          placeholder="Name (e.g. Invoices)"
          value={newName}
          onChange={(event) => setNewName(event.target.value)}
          required
        />
        <textarea
          placeholder="Description (helps the assistant decide when to apply it)"
          value={newDescription}
          onChange={(event) => setNewDescription(event.target.value)}
          required
        />
        <button type="submit" disabled={creating}>
          {creating ? "Adding..." : "Add category"}
        </button>
      </form>
    </div>
  );
}
