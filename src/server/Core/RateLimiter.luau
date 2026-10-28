-- Token bucket rate limiter keyed by any value (usually a UserId).
local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- capacity = burst size, refill = tokens per second
function RateLimiter.new(capacity: number, refill: number)
	return setmetatable({ capacity = capacity, refill = refill, buckets = {} }, RateLimiter)
end

function RateLimiter:check(key, now: number): boolean
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.capacity, at = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.at)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refill)
	bucket.at = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:forget(key)
	self.buckets[key] = nil
end

return RateLimiter
