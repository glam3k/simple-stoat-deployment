import Revolt from "revolt-nodejs-bindings";
import { API } from "revolt.js";

import { callProcedure, createCollectionFn } from "..";

export type RevoltUser = API.User;
export type RevoltUserInfo = Omit<RevoltUser, "relations"> & {
  relations: {
    friends: number;
  };
};

export function isRestrictedUser(user: RevoltUser) {
  return user._id === process.env.PLATFORM_ACCOUNT_ID;
}

/**
 * Generate Stoat user information as a smaller payload
 * @param user User
 * @returns Stripped User
 */
export function revoltUserInfo(user: RevoltUser): RevoltUserInfo {
  return {
    ...user,
    relations: {
      friends: user.relations?.filter((x) => x.status === "Friend").length || 0,
    },
  };
}

const userCol = createCollectionFn<RevoltUser>("revolt", "users");

/**
 * Fetch a user by given ID
 * @param id ID
 * @returns User if exists
 */
export function fetchUserById(id: string) {
  return userCol().findOne({ _id: id });
}

/**
 * Suspend user by given ID
 * @param userId User ID
 * @param duration Duration (in days), set to 0 for indefinite
 * @param reasons Reasons
 */
export async function suspendUser(
  userId: string,
  duration: number,
  reasons: string[],
) {
  let user = await callProcedure(Revolt.database_fetch_user, userId);

  await callProcedure(
    Revolt.proc_users_suspend,
    user,
    duration,
    reasons.join("|"),
  );
}
