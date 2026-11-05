import React, { useState, useEffect } from 'react';
import { 
  collection, 
  onSnapshot, 
  doc, 
  updateDoc 
} from 'firebase/firestore';
import { db } from '../firebase';
import { useAuth } from '../context/AuthContext';
import { 
  UserPlus, 
  Shield, 
  ShieldCheck, 
  Search, 
  UserCheck, 
  Users, 
  AlertCircle 
} from 'lucide-react';

export default function UsersView() {
  const { currentUser, userRole, isOwner, isAdmin, registerBeekeeper } = useAuth();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('ALL');
  
  // Modal state
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newEmail, setNewEmail] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newName, setNewName] = useState('');
  const [newRole, setNewRole] = useState('beekeeper');
  const [modalLoading, setModalLoading] = useState(false);
  const [feedback, setFeedback] = useState(null);

  // Customized Role Confirmation Modal state
  const [pendingRoleChange, setPendingRoleChange] = useState(null);
  const [isUpdatingRole, setIsUpdatingRole] = useState(false);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, 'users'), (snapshot) => {
      const list = snapshot.docs.map(d => ({
        id: d.id,
        ...d.data(),
        createdAtFormatted: d.data().createdAt?.toDate 
            ? d.data().createdAt.toDate().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) 
            : 'Recent'
      }));
      setUsers(list);
      setLoading(false);
    }, (err) => {
      console.error("Error fetching users:", err);
      setLoading(false);
    });

    return () => unsub();
  }, []);

  // Access guard: Beekeepers cannot access the user directory
  if (!isAdmin) {
    return (
      <div className="p-8 max-w-xl mx-auto text-center space-y-4 pt-16">
        <h2 className="text-base font-bold text-slate-900">Access Restricted</h2>
        <p className="text-xs text-slate-500">
          The User Directory & Role Control console is restricted to Apiary Admins and Owners.
        </p>
      </div>
    );
  }

  const handleInitiateRoleChange = (targetUserId, targetNewRole, memberName, currentRole) => {
    if (!isOwner) {
      setFeedback({ 
        type: 'error', 
        text: "Permission Denied: Only an account with the Owner role can modify user privileges." 
      });
      setTimeout(() => setFeedback(null), 3500);
      return;
    }

    if (targetNewRole === currentRole) return;

    // Open customized confirmation modal in middle of screen
    setPendingRoleChange({
      targetUserId,
      targetNewRole,
      memberName,
      currentRole
    });
  };

  const confirmExecuteRoleChange = async () => {
    if (!pendingRoleChange) return;
    setIsUpdatingRole(true);
    const { targetUserId, targetNewRole, memberName } = pendingRoleChange;

    try {
      const userRef = doc(db, 'users', targetUserId);
      await updateDoc(userRef, { role: targetNewRole });
      setFeedback({ 
        type: 'success', 
        text: `Role for "${memberName}" successfully updated to ${targetNewRole.toUpperCase()}.` 
      });
      setTimeout(() => setFeedback(null), 3500);
      setPendingRoleChange(null);
    } catch (e) {
      setFeedback({ type: 'error', text: e.message });
    } finally {
      setIsUpdatingRole(false);
    }
  };

  const handleCreateUser = async (e) => {
    e.preventDefault();
    if (!newEmail || !newPassword) return;
    setModalLoading(true);
    try {
      await registerBeekeeper(newEmail, newPassword, newName, newRole);
      setIsModalOpen(false);
      setNewEmail('');
      setNewPassword('');
      setNewName('');
      setNewRole('beekeeper');
      setFeedback({ type: 'success', text: `New account registered successfully with role: ${newRole.toUpperCase()}.` });
      setTimeout(() => setFeedback(null), 3500);
    } catch (err) {
      setFeedback({ type: 'error', text: err.message });
    } finally {
      setModalLoading(false);
    }
  };

  const filteredUsers = users.filter((u) => {
    const matchesSearch = 
      (u.displayName || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
      (u.email || '').toLowerCase().includes(searchQuery.toLowerCase());
    
    if (roleFilter === 'ALL') return matchesSearch;
    return matchesSearch && (u.role || 'beekeeper').toLowerCase() === roleFilter.toLowerCase();
  });

  const getRoleBadge = (role) => {
    const r = (role || 'beekeeper').toLowerCase();
    if (r === 'owner') {
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded text-[11px] font-mono font-medium bg-amber-50 text-amber-900 border border-amber-300">
          <ShieldCheck className="w-3 h-3 text-amber-600" />
          <span>OWNER</span>
        </span>
      );
    }
    if (r === 'admin') {
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded text-[11px] font-mono font-medium bg-indigo-50 text-indigo-900 border border-indigo-200">
          <Shield className="w-3 h-3 text-indigo-600" />
          <span>ADMIN</span>
        </span>
      );
    }
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded text-[11px] font-mono font-medium bg-slate-100 text-slate-700 border border-slate-200">
        <UserCheck className="w-3 h-3 text-slate-500" />
        <span>BEEKEEPER</span>
      </span>
    );
  };

  return (
    <div className="p-3 sm:p-5 md:p-6 max-w-7xl mx-auto space-y-5 sm:space-y-6 min-w-0">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-slate-200/80 gap-3">
        <div>
          <h2 className="text-lg font-bold text-slate-900 tracking-tight">User Directory & Role Control</h2>
          <p className="text-xs text-slate-500">Manage apiary permissions, 3-tier access classifications, and staff roster</p>
        </div>

        <button
          onClick={() => setIsModalOpen(true)}
          className="flex items-center gap-1.5 px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white font-medium rounded-lg text-xs transition shadow-2xs"
        >
          <UserPlus className="w-3.5 h-3.5" />
          <span>New User</span>
        </button>
      </div>

      {feedback && (
        <div className={`p-3 rounded-lg text-xs font-medium border flex items-center gap-2 ${
          feedback.type === 'success' 
            ? 'bg-emerald-50 text-emerald-800 border-emerald-200' 
            : 'bg-red-50 text-red-800 border-red-200'
        }`}>
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{feedback.text}</span>
        </div>
      )}

      {/* 3-Tier Role Capabilities Explainer */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-xs">
        <div className="p-3 bg-amber-50/60 rounded-xl border border-amber-200/80 space-y-1">
          <div className="font-bold text-amber-900 flex items-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-amber-600" />
            <span>Owner Role (Super Admin)</span>
          </div>
          <p className="text-[11px] text-amber-800 leading-relaxed">
            Full unrestricted control. <strong>Only Owners</strong> have permission to promote, demote, or assign roles to other team members.
          </p>
        </div>

        <div className="p-3 bg-indigo-50/50 rounded-xl border border-indigo-200/80 space-y-1">
          <div className="font-bold text-indigo-900 flex items-center gap-1.5">
            <Shield className="w-3.5 h-3.5 text-indigo-600" />
            <span>Admin Role (Apiary Manager)</span>
          </div>
          <p className="text-[11px] text-indigo-800 leading-relaxed">
            Full operations: add/delete hives, manage alerts, review audio, and export telemetry. <strong>Cannot</strong> promote or modify user roles.
          </p>
        </div>

        <div className="p-3 bg-slate-50 rounded-xl border border-slate-200/80 space-y-1">
          <div className="font-bold text-slate-800 flex items-center gap-1.5">
            <UserCheck className="w-3.5 h-3.5 text-slate-500" />
            <span>Beekeeper Role (Field Worker)</span>
          </div>
          <p className="text-[11px] text-slate-600 leading-relaxed">
            Standard apiary personnel with real-time field telemetry and condition monitoring. Hive registration, exports, and history are restricted.
          </p>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-3">
        <div className="w-full sm:w-72 relative">
          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-2.5" />
          <input
            type="text"
            placeholder="Filter by name or email..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-1.5 bg-white border border-slate-200 rounded-lg text-xs text-slate-900 placeholder:text-slate-400 focus:border-slate-400 focus:outline-none transition shadow-2xs"
          />
        </div>

        <div className="flex items-center gap-1.5 self-start sm:self-auto">
          {['ALL', 'OWNER', 'ADMIN', 'BEEKEEPER'].map((role) => (
            <button
              key={role}
              onClick={() => setRoleFilter(role)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium transition ${
                roleFilter === role
                  ? 'bg-slate-900 text-white font-semibold shadow-2xs'
                  : 'bg-white text-slate-600 border border-slate-200 hover:bg-slate-50'
              }`}
            >
              {role}
            </button>
          ))}
        </div>
      </div>

      {/* Enterprise Users Table */}
      <div className="bg-white rounded-xl border border-slate-200/90 shadow-2xs overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs min-w-[620px]">
          <thead className="bg-slate-50/75 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[11px]">
            <tr>
              <th className="py-3 px-5">Member</th>
              <th className="py-3 px-5">Role Assignment</th>
              <th className="py-3 px-5">Status</th>
              <th className="py-3 px-5">Joined</th>
              <th className="py-3 px-5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 text-slate-700">
            {filteredUsers.length === 0 ? (
              <tr>
                <td colSpan="5" className="text-center py-8 text-slate-400">
                  No registered accounts found in this category.
                </td>
              </tr>
            ) : (
              filteredUsers.map((u) => {
                const role = (u.role || 'beekeeper').toLowerCase();
                const isCurrentLoggedUser = u.id === currentUser?.uid;

                return (
                  <tr key={u.id} className="hover:bg-slate-50/60 transition">
                    <td className="py-3.5 px-5">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-lg bg-slate-100 text-slate-700 border border-slate-200 flex items-center justify-center font-bold text-xs shrink-0">
                          {(u.displayName || u.email || 'B').charAt(0).toUpperCase()}
                        </div>
                        <div>
                          <div className="font-medium text-slate-900 flex items-center gap-1.5">
                            <span>{u.displayName || 'Beekeeper'}</span>
                            {isCurrentLoggedUser && (
                              <span className="text-[10px] text-slate-400 font-mono">(You)</span>
                            )}
                          </div>
                          <span className="text-[11px] text-slate-400 block">{u.email}</span>
                        </div>
                      </div>
                    </td>

                    <td className="py-3.5 px-5">
                      {getRoleBadge(role)}
                    </td>

                    <td className="py-3.5 px-5">
                      <span className="text-xs text-slate-600 font-medium">
                        Active
                      </span>
                    </td>

                    <td className="py-3.5 px-5 text-slate-500 text-[11px] font-mono">
                      {u.createdAtFormatted}
                    </td>

                    {/* Actions Column: Strictly enforces Owner-only role modification */}
                    <td className="py-3.5 px-5 text-right">
                      {isOwner ? (
                        <div className="flex items-center justify-end gap-1.5">
                          {isCurrentLoggedUser ? (
                            <span className="text-[11px] text-slate-400 font-mono italic">(Current Account)</span>
                          ) : (
                            <select
                              value={role}
                              onChange={(e) => handleInitiateRoleChange(u.id, e.target.value, u.displayName || u.email, role)}
                              className="px-2.5 py-1 text-xs font-semibold rounded-md border border-slate-200 bg-white text-slate-800 hover:border-slate-300 focus:outline-none focus:border-amber-500 transition shadow-2xs cursor-pointer"
                            >
                              <option value="owner">Assign: Owner</option>
                              <option value="admin">Assign: Admin</option>
                              <option value="beekeeper">Assign: Beekeeper</option>
                            </select>
                          )}
                        </div>
                      ) : (
                        <span className="px-2.5 py-1 text-[11px] font-mono text-slate-400 bg-slate-50 border border-slate-200 rounded-md">
                          Promotion Locked
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
        </div>
      </div>

      {/* Modal: New User */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-xl max-w-sm w-full p-5 shadow-xl border border-slate-200 space-y-4">
            <div className="flex items-center justify-between pb-3 border-b border-slate-100">
              <h3 className="font-semibold text-slate-900 text-sm">Create Apiary Account</h3>
              <button onClick={() => setIsModalOpen(false)} className="text-slate-400 hover:text-slate-700 text-sm font-bold p-1">
                ✕
              </button>
            </div>

            <form onSubmit={handleCreateUser} className="space-y-3.5 text-xs">
              <div>
                <label className="block text-slate-600 font-medium mb-1">Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. John Doe"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-slate-400 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-600 font-medium mb-1">Email</label>
                <input
                  type="email"
                  required
                  placeholder="john@beeware.com"
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-slate-400 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-600 font-medium mb-1">Password</label>
                <input
                  type="password"
                  required
                  minLength={6}
                  placeholder="••••••••"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-slate-400 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-slate-600 font-medium mb-1">Role Classification</label>
                <select
                  value={newRole}
                  onChange={(e) => setNewRole(e.target.value)}
                  className="w-full px-3 py-1.5 border border-slate-200 rounded-lg text-slate-900 focus:border-slate-400 focus:outline-none bg-white font-medium"
                >
                  <option value="beekeeper">Beekeeper (Field Worker)</option>
                  <option value="admin">Admin (Apiary Operations)</option>
                  {isOwner && <option value="owner">Owner (Super Admin)</option>}
                </select>
              </div>

              <div className="pt-2 flex justify-end gap-2 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-3 py-1.5 text-slate-600 hover:bg-slate-100 rounded-lg font-medium transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={modalLoading}
                  className="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 text-white rounded-lg font-medium transition shadow-2xs"
                >
                  {modalLoading ? 'Creating...' : 'Create Account'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Customized Confirmation Modal for Changing Roles */}
      {pendingRoleChange && (
        <div className="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200 text-center space-y-4 animate-in zoom-in-95 duration-150">
            <div className="w-10 h-10 mx-auto rounded-full bg-amber-50 text-amber-600 flex items-center justify-center">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <div className="space-y-1">
              <h3 className="text-base font-bold text-slate-900">Confirm Role Modification</h3>
              <p className="text-xs text-slate-500">
                Are you sure you want to update permissions for this account?
              </p>
            </div>

            <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200/80 space-y-2 text-xs">
              <div className="font-semibold text-slate-900 truncate">
                {pendingRoleChange.memberName}
              </div>
              <div className="flex items-center justify-center gap-2.5 pt-0.5">
                <span className="px-2.5 py-0.5 rounded text-[11px] font-mono font-bold bg-slate-200 text-slate-700">
                  {pendingRoleChange.currentRole.toUpperCase()}
                </span>
                <span className="text-slate-400 font-bold">➔</span>
                <span className={`px-2.5 py-0.5 rounded text-[11px] font-mono font-bold border ${
                  pendingRoleChange.targetNewRole === 'owner' 
                    ? 'bg-amber-50 text-amber-900 border-amber-300' 
                    : pendingRoleChange.targetNewRole === 'admin' 
                    ? 'bg-indigo-50 text-indigo-900 border-indigo-200' 
                    : 'bg-slate-100 text-slate-700 border-slate-200'
                }`}>
                  {pendingRoleChange.targetNewRole.toUpperCase()}
                </span>
              </div>
            </div>

            <p className="text-[11px] text-slate-500 leading-relaxed px-2">
              {pendingRoleChange.targetNewRole === 'owner' && 'This user will receive full privileges, including the ability to promote, demote, and modify other accounts.'}
              {pendingRoleChange.targetNewRole === 'admin' && 'This user will receive full operational access across hives, alerts, and exports. Promoting other users remains restricted.'}
              {pendingRoleChange.targetNewRole === 'beekeeper' && 'This user will be reverted to standard field monitoring view access.'}
            </p>

            <div className="flex items-center justify-center gap-2.5 pt-2">
              <button
                type="button"
                onClick={() => setPendingRoleChange(null)}
                disabled={isUpdatingRole}
                className="flex-1 px-4 py-2 text-slate-700 hover:bg-slate-100 rounded-lg text-xs font-semibold transition border border-slate-200"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmExecuteRoleChange}
                disabled={isUpdatingRole}
                className="flex-1 px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-lg text-xs font-semibold transition shadow-sm"
              >
                <span>{isUpdatingRole ? 'Updating...' : 'Confirm Update'}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
