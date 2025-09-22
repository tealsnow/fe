import { Brand } from "effect";
import * as uuid from "uuid";

export type UUID = string & Brand.Brand<"UUID">;

const UUIDRaw = Brand.refined<UUID>(
  (str) => uuid.validate(str),
  (str) => Brand.error(`Expected '${str}' to be a valid uuid`),
);

export const makeUUID = (): UUID => UUID(uuid.v4());

export const UUID = Object.assign(UUIDRaw, {
  make: makeUUID,
});

export default UUID;
