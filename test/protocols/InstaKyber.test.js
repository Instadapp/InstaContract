// const { assertRevert } = require('./helpers/general')

const InstaKyber = artifacts.require('InstaKyber')

contract('InstaKyber', accounts => {
  let instaKyber

  beforeEach(async () => {
    instaKyber = await InstaKyber.new(accounts[0])
  })

  it('should have an owner', async () => {
    const addressRegistry = await instaKyber.addressRegistry()
    assert.isTrue(addressRegistry !== 0)
  })
})
