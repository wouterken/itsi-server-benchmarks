# frozen_string_literal: true

run(
  proc do
    primes_found = compute_primes(1000)
    body = "Found #{primes_found} prime numbers up to 1000.\n"
    [200, { 'content-type' => 'text/plain' }, [body]]
  end
)

def prime?(n)
  return false if n < 2
  return true if n == 2
  return false if n.even?

  max = Math.sqrt(n).to_i
  (3..max).step(2).none? { |i| (n % i).zero? }
end

def compute_primes(limit)
  count = 0
  (2..limit).each do |n|
    count += 1 if prime?(n)
  end
  count
end
